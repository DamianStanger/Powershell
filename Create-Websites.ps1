param(
    [string] $topLevelDomain
)

#Usage   .\Create-Websites.ps1 -topLevelDomain com
#Usage   .\Create-Websites.ps1 -topLevelDomain co.uk

if($topLevelDomain -eq "")
{
    throw [System.ArgumentException] "topLevelDomain '$topLevelDomain' must have values"
}

import-module WebAdministration

write-host "topLevelDomain is set to '$topLevelDomain'"

$VirtualWebRoot = "c:\virtual"

function createDirectory ($folderPath) {
    write-host "checking path '$folderPath'"
    if((Test-Path $folderPath) -ne $True) {
        new-item -Path $folderPath -Type directory 
    }
}

createDirectory "$VirtualWebRoot\foobarui-http.foobar.$topLevelDomain"
createDirectory "$VirtualWebRoot\foobarui.foobar.$topLevelDomain.blue"
createDirectory "$VirtualWebRoot\foobarui.foobar.$topLevelDomain.green"
createDirectory "$VirtualWebRoot\foobarapi.foobar.$topLevelDomain.blue"
createDirectory "$VirtualWebRoot\foobarapi.foobar.$topLevelDomain.green"

function setupWebsite($name, $hostnamePart, $ssl, $physicalPathColor)
{
    if($physicalPathColor){
        $physicalPathColor = ".$physicalPathColor"
    }
    $virtualRootOfSite = "$VirtualWebRoot\$name.foobar.$topLevelDomain$physicalPathColor"
    $virtualRootOfSite = $virtualRootOfSite -replace '-staging'
    $websiteName = "$name.foobar.$topLevelDomain"
    $appPoolName = $websiteName + "_pool"
    $hostname = "$hostnamePart.foobar.$topLevelDomain"

    Write-Host "SetupWebsite '$websiteName' : sll=$ssl at '$virtualRootOfSite' with pool '$appPoolName' on host '$hostname'"
    
    New-WebAppPool $appPoolName -ErrorAction ignore

    $pool = Get-Item "IIS:\AppPools\$appPoolName"
    $pool.processModel.identityType = 4 #4=applicationpool 2=NetworkService
    $pool.managedRuntimeVersion = "v4.0"
    $pool | Set-Item
    $pool.Start()

    if($ssl){
        New-Website -Name $websiteName -PhysicalPath $virtualRootOfSite -ApplicationPool $appPoolName -ErrorAction Stop -HostHeader $hostname -IPAddress "*" -Ssl -port 443        
    }
    else{
        New-Website -Name $websiteName -PhysicalPath $virtualRootOfSite -ApplicationPool $appPoolName -ErrorAction Stop -HostHeader $hostname -IPAddress "*"
        Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\$websiteName" -Value @{enabled="true";destination="https://$hostname";exactDestination="false";httpResponseStatus="Found"}
    }
}

function applyCert($pattern){
    $cert = dir cert:\localmachine\my | where-object{$_.subject -like $pattern}
    if(!$cert){
        throw [System.Exception] "No ssl cert found that matches the search '$pattern'"
    }
    new-item "IIS:\SslBindings\0.0.0.0!443" -Value $cert
}

setupWebsite "foobarui-http" "foobarui-test" $false ""
setupWebsite "foobarui" "foobarui-test" $true "green" 
setupWebsite "foobarui-staging" "foobarui-test-staging" $true "blue"
setupWebsite "foobarapi" "foobarapi-test" $true "green" 
setupWebsite "foobarapi-staging" "foobarapi-test-staging" $true "blue"

applyCert("*.foobar.*")

#Usefull powershell whilst dealing with websites and iis
#PS C:\> Import-Module WebAdministration
#PS C:\> dir IIS:\SslBindings
#PS C:\> New-Website -Name foo.foobar.ca -PhysicalPath c:\virtual -ErrorAction Stop -HostHeader foo.foobar.ca -IPAddress "*" -Ssl -port 443
#PS C:\> $cert = dir cert:\localmachine\my | where-object{$_.subject -like "*.foobar.*"}
#PS C:\> new-item "IIS:\SslBindings\0.0.0.0!443" -Value $cert

#PS C:\> dir IIS:\AppPools | where-object{$_.Name -like "*.foobar.co*"} | Remove-Item
#PS C:\> dir IIS:\Sites | where-object{$_.Name -like "*.foobar.co*"} | remove-item
#PS C:\> dir IIS:\SslBindings | remove-item