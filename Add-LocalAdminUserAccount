Function Add-LocalUserAdminAccount{
    param (
     [parameter(Mandatory=$true)]
        [string[]]$ComputerNames=$env:computername, 
     [parameter(Mandatory=$true)]
        [string[]]$UserNames, 
     [parameter(Mandatory=$true)]
        [string]$Password
    )    

    foreach ($computer in $ComputerNames){
        foreach ($userName in $UserNames){    
            Write-Host "setting up user $userName on $computer"

            [ADSI]$server="WinNT://$computer"
            $user=$server.Create("User",$userName)
            $user.SetPassword($Password)
            $user.Put("FullName","$userName-admin")
            $user.Put("Description","Scripted admin user for $userName")

            #PasswordNeverExpires
            $flag=$User.UserFlags.value -bor 0x10000
            $user.put("userflags",$flag)        

            $user.SetInfo()             

            [ADSI]$group = “WinNT://$computer/Administrators,group”
            write-host "Adding" $user.path "to " $group.path
            $group.add($user.path)

            [ADSI]$group = “WinNT://$computer/Remote Desktop Users,group”
            write-host "Adding" $user.path "to " $group.path
            $group.add($user.path)
        }
    }
}

[string[]]$computerNames = "computer1", "computer2"
[string[]]$accountNames = "ops", "buildagent"

Add-LocalUserAccount -ComputerNames $computerNames -UserNames $accountNames -Password mysecurepassword
