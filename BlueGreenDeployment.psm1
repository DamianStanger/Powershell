Import-Module webadministration

$VirtualDirPath = "c:\virtual\"
$VirtualBackupPath = "c:\virtual_backup\"

function Deploy-Staging 
{
    param (     
        [string] $Source,     
        [string] $WebsiteName,
        [string] $DomainName
    )     

    Write-Host "Deploy-Staging starting for '$WebsiteName' on domain '$DomainName'"

    if($Source -eq "" -Or $WebsiteName -eq "" -Or $DomainName -eq "")
    {
        throw [System.ArgumentException] "Source '$Source', WebsiteName '$WebsiteName', and DomainName '$DomainName' must have values"
    }

    $WebsitePhysicalPath = "$WebsiteName.$DomainName"

    $SourcePath = Resolve-Path $Source
    $DestinationPath = "$VirtualDirPath$WebsitePhysicalPath.blue"

    if(IsLiveOnBlue $WebsiteName $DomainName)
    {
        $DestinationPath = "$VirtualDirPath$WebsitePhysicalPath.green"
    }

    Write-Host "Deploying '$SourcePath' to '$DestinationPath'"
    
    Remove-Item $DestinationPath -Recurse -Force -ErrorAction Stop
    Set-Content -Value $DestinationPath -Path $SourcePath\bluegreen.txt
    New-Item $DestinationPath -Type Directory  -ErrorAction Stop
    Copy-Item $SourcePath\* $DestinationPath -Recurse -Force -ErrorAction Stop
    RewriteLogFileLocation -physicalPath $DestinationPath -isStaging $true

    Write-Host "Deploy-Staging complete for $WebsiteName"
}

function Backup-Live 
{
    param (     
        [string] $WebsiteName,
        [string] $DomainName
    )

    Write-Host "Backup-Live starting for '$WebsiteName' on domain '$DomainName'"

    if($WebsiteName -eq "" -Or $DomainName -eq ""){
        throw [System.ArgumentException] "WebsiteName '$WebsiteName' and DomainName '$DomainName' must have a value"
    }

    $WebsitePhysicalPath = "$WebsiteName.$DomainName"

    $CurrentDateFormatted = Get-Date -Format yyyyMMddHHmmss
    $BackupPath = "$VirtualBackupPath$WebsitePhysicalPath\$CurrentDateFormatted"
    $FullVirtualPath = "$VirtualDirPath$WebsitePhysicalPath.green"

    if(IsLiveOnBlue $WebsiteName $DomainName)
    {
        $FullVirtualPath = "$VirtualDirPath$WebsitePhysicalPath.blue"
    }
    
    Write-Host "Backing up '$FullVirtualPath' to '$BackupPath'"

    New-Item -Path $BackupPath -Type Directory -Force -ErrorAction Stop
    Copy-Item $FullVirtualPath\* $BackupPath -Recurse -Force -ErrorAction Stop

    Write-Host "Backup-Live complete for '$WebsiteName'"
}

function Switch-BlueGreen 
{
    param (     
        [string] $WebsiteName,
        [string] $DomainName
    )
    
    Write-Host "Switch-BlueGreen starting for '$WebsiteName' on domain '$DomainName'"

    if($WebsiteName -eq "" -Or $DomainName -eq ""){
        throw [System.ArgumentException] "Website name '$WebsiteName' and DomainName '$DomainName' must have a value."
    }

    $WebsitePhysicalPath = "$WebsiteName.$DomainName"

    $liveSite = "IIS:\Sites\$WebsiteName.$DomainName"
    $stagingSite = "IIS:\Sites\$WebsiteName-staging.$DomainName"

    $blueWebsitePath = "$VirtualDirPath$WebsitePhysicalPath.blue"
    $greenWebsitePath = "$VirtualDirPath$WebsitePhysicalPath.green"

    if(IsLiveOnBlue $WebsiteName $DomainName)
    {
        Write-Host '>>> Live is currently on blue; changing to green...'
        Set-ItemProperty $liveSite -Name physicalPath -Value $greenWebsitePath -ErrorAction Stop
        Set-ItemProperty $stagingSite -Name physicalPath -Value $blueWebsitePath -ErrorAction Stop

        RewriteLogFileLocation -physicalPath $greenWebsitePath -isStaging $false
        RewriteLogFileLocation -physicalPath $blueWebsitePath -isStaging $true
    }
    else
    {
        Write-Host '>>> Live is currently on green; changing to blue...'
        Set-ItemProperty $liveSite -Name physicalPath -Value $blueWebsitePath -ErrorAction Stop
        Set-ItemProperty $stagingSite -Name physicalPath -Value $greenWebsitePath -ErrorAction Stop

        RewriteLogFileLocation -physicalPath $blueWebsitePath -isStaging $false
        RewriteLogFileLocation -physicalPath $greenWebsitePath -isStaging $true
    }

    Write-Host "Switch-BlueGreen complete for '$WebsiteName'"
}

function IsLiveOnBlue($WebsiteName, $domainName)
{
    $liveSite = "IIS:\Sites\$WebsiteName.$domainName"
    $stagingSite = "IIS:\Sites\$WebsiteName-staging.$domainName"

    $livePhysicalPath = GetPhysicalPath $liveSite 1
    $stagingPhysicalPath = GetPhysicalPath $stagingSite 1

    $liveIsOnBlue = $livePhysicalPath.EndsWith("blue")    

    if($livePhysicalPath -eq $stagingPhysicalPath)
    {
        throw [System.Exception] ">>> Live and staging point to the same virtual directory. Which is '$livePhysicalPath'."
    }

    Write-Host "Staging='$stagingPhysicalPath' live='$livePhysicalPath' liveIsOnBlue='$liveIsOnBlue'"

    return $liveIsOnBlue
}

function GetPhysicalPath($website, [int] $callCount)
{
    write-host "*** GetPhysicalPath for '$website' callCount $callCount"

    if($callCount -gt 4){        
        throw [System.Exception] ">>> Failed $callCount times to get '$website'"
    }

    $websiteProperties = Get-ItemProperty $website
    $physicalPath = $websiteProperties.PhysicalPath
   
    if($physicalPath.GetType().Name -eq "String")
    {
        write-host "*** physicalPath for '$website' is '$physicalPath'"
        return $physicalPath
    }

    $callCount = $callCount + 1
    return GetPhysicalPath $website $callCount
}

function RewriteLogFileLocation([string]$physicalPath, [bool]$isStaging)
{
    $configFile = $physicalPath + "\web.config"
    Write-Host '>>> Starting to rewrite log file location for file '$configFile'...'

    $xdoc = new-object System.Xml.XmlDocument
    $xdoc.load($configFile)

    $node = $xdoc.configuration.log4net.appender.file

    if(!$node)
    {
        Write-Host "Cannot find the correct node in '$configFile'. Expecting to find log4net/appender/file. Not attempting to rewrite."
    }
    else
    {
        $currentNodeValue = $node.value
        $newNodeValue = $currentNodeValue -replace "(-staging)+\.log$", ".log"
    
        if($isStaging)
        {
            Write-Host ">>>>>> Suffixing for staging..."
            $newNodeValue = $newNodeValue -replace "\.log$", "-staging.log"
            Write-Host $newNodeValue
        }

        $node.value = $newNodeValue
        $xdoc.Save($configFile)
    
        Write-Host '>>> Completed rewriting log file location for file '$configFile'...'
    }
}

export-modulemember -function Deploy-Staging
export-modulemember -function Backup-Live
export-modulemember -function Switch-BlueGreen

#Examples
#Deploy-Staging -Source . -WebsiteName foobarapi -DomainName foobar.co.uk
#Deploy-Staging -source c:\tmp -websiteName foobarapi -domainName foobar.co.uk
#Backup-Live -WebsiteName foobarapi -DomainName foobar.co.uk
#Switch-BlueGreen -WebsiteName foobarapi -DomainName foobar.co.uk