

#Global Variables
$RegRoot = 'HKLM:SOFTWARE\HobbyLobby\Beater'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$LogLevel = 'Debug'
$ConsoleLevel = 'Debug'

Function Set-BTRServerConfig {
     Param (
        [Parameter(Mandatory=$True)]$Config
    )

    #Set Root Path
    If ($Config.RootPath) {
        $Default = $Config.Rootpath
    }Else{
        $Default = 'C:\Beater'
    }
    $RootPath = Read-Host "Root Path for Beater? [$Default]:"
    If ($RootPath) {       
        $Config.RootPath = $Rootpath
    }Else{
        $Config.RootPath = $Default
    }
}

Function Set-BTRInstanceConfig {
     Param (
        [Parameter(Mandatory=$True)]$Config,
        [HashTable]$Instance
    )

    #Set Name
    If ($Instance.Name) {
        $Default = $Instance.Name
    }Else{
        $Default = 'Beater'
    }
    $Name = Read-Host "Instance Name? [$Default]:"
    If ($Name) {       
        $Instance.Name = $Name
    }Else{
        $Instance.Name = $Default
    }

}

Function Set-BTRInstanceConfig {
     Param (
        [Parameter(Mandatory=$True)]$Config,
        [HashTable]$OldInstance
    )

    $NewInstance = @{}

    #Set Name
    If ($OldInstance.Name) {
        $Default = $OldInstance.Name
    }Else{
        $Default = "Beater"
    }
    Do {
        $New = Read-Host "Instance Name? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{3,15}$")
    $NewInstance.Name = $New

    #Set AppFolder
    If ($OldInstance.AppFolder) {
        $Default = $OldInstance.AppFolder
    }Else{
        $Default = "$($Config.RootPath)\Apps"
    }
    Do {
        $New = Read-Host "Path to application install files? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.AppFolder = $New

    #Set Certificate Folder
    If ($OldInstance.CertFolder) {
        $Default = $OldInstance.CertFolder
    }Else{
        $Default = "$($Config.RootPath)\Certificates"
    }
    Do {
        $New = Read-Host "Path to certificate folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.CertFolder = $New

    #Set Working Folder
    If ($OldInstance.WorkingFolder) {
        $Default = $OldInstance.WorkingFolder
    }Else{
        $Default = "$($Config.RootPath)\Working"
    }
    Do {
        $New = Read-Host "Path to working folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.WorkingFolder = $New

    #Set VM Folder
    If ($OldInstance.VMPath) {
        $Default = $OldInstance.VMPath
    }Else{
        $Default = "$($Config.RootPath)\$($NewInstance.Name)\Virtual Machines"
    }
    Do {
        $New = Read-Host "Path to VM Folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.VMPath = $New

    #Set HDD Folder
    If ($OldInstance.HDDPath) {
        $Default = $OldInstance.HDDPath
    }Else{
        $Default = "$($Config.RootPath)\$($NewInstance.Name)\Virtual Hard Disks"
    }
    Do {
        $New = Read-Host "Path to HDD folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.HDDPath = $New

    #Set Sanpshot Folder
    If ($OldInstance.SnapShotPath) {
        $Default = $OldInstance.SnapShotPath
    }Else{
        $Default = "$($Config.RootPath)\$($NewInstance.Name)\Snapshots"
    }
    Do {
        $New = Read-Host "Path to snapshot folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.SnapShotPath = $New

    #Set VM Temp Folder
    If ($OldInstance.VMTempFolder) {
        $Default = $OldInstance.VMTempFolder
    }Else{
        $Default = "C:\Temp"
    }
    Do {
        $New = Read-Host "Path to temp folder on VMs? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.VMTempFolder = $New

    #Set Use NAT
    If ($OldInstance.UseNAT) {
        $Default = $OldInstance.UseNAT
    }Else{
        $Default = "Y"
    }
    Do {
        $New = Read-Host "Use NAT on switch (Y/N) [$Default]"
        If (!($New)) {
            $New = $Default
        }Else {
            $New = $New.ToUpper()
        }
    }Until ($New -Match '[YN]')
    $NewInstance.UseNAT = $New

    #Set IP
    If ($OldInstance.IPPrefix) {
        $Default = $OldInstance.IPPrefix
    }Else{
        $Default = "192.168.$(Get-Random -Minimum 2 -Maximum 254)"
    }
    Do {
        $New = Read-Host "Network Address [$Default]"
        If (!($New)) {
            $New = $Default
        }ElseIf ($New.Substring($New.Length -2) -eq '.0') {
            $New = $New.Substring(0, $New.Length -2)
        }
    }Until ($New -Match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){2}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
    $NewInstance.IPPrefix = $New

    #Set Subnet Mask and Subnet Mask Length
    If ($OldInstance.SubnetMask) {
        $Default = $OldInstance.SubnetMask
    }Else{
        $Default = "255.255.255.0"
    }
    Do {
        $New = Read-Host "Subnet Mask [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ((($New.Split(".") | ForEach { ([Convert]::ToSTring($_,2)).PadLeft(8,'0') }) -join "").IndexOf('01') -eq -1)
    $NewInstance.SubnetMask = $New
    $NewInstance.SubnetLength =  [RegEx]::Matches((($New.Split(".") | ForEach { ([Convert]::ToSTring($_,2)).PadLeft(8,'0') }) -join ""),'1').count

    #Set Gateway
    If ($OldInstance.Gateway) {
        $Default = $OldInstance.Gateway
    }Else{
        $Default = "$($NewInstance.IPPrefix).1"
    }
    Do {
        $New = Read-Host "Default Gateway [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
    $NewInstance.Gateway = $New

    #Set Switch Name
    If ($OldInstance.SwitchName) {
        $Default = $OldInstance.SwitchName
    }Else{
        $Default = "$($NewInstance.Name)"
    }
    $New = Read-Host "Name of Switch [$Default]"
    If (!($New)) {
        $New = $Default
    }
    $NewInstance.SwitchName = $New

    #Set Domain Name
    If ($OldInstance.DomainName) {
        $Default = $OldInstance.DomainName
    }Else{
        $Default = "$($NewInstance.Name).local"
    }
    Do {
        $New = Read-Host "Name of Domain [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match “^((?!-))(xn--)?[a-z0-9][a-z0-9-_]{0,61}[a-z0-9]{0,1}\.(xn--)?([a-z0-9\-]{1,61}|[a-z0-9-]{1,30}\.[a-z]{2,})$”)
    $NewInstance.DomainName = $New

    #Set NB Domain Name
    If ($OldInstance.NBDomainName) {
        $Default = $OldInstance.NBDomainName
    }Else{
        $Default = $NewInstance.DomainName.Split('.')[0]
    }
    Do {
        $New = Read-Host "NetBIOS Name of Domain [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$")
    $NewInstance.NBDomainName = $New

    #Set Admin Account Name
    If ($OldInstance.AdminName) {
        $Default = $OldInstance.AdminName
    }Else{
        $Default = "Administrator"
    }
    Do {
        $New = Read-Host "Administrator account? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$")
    $NewInstance.AdminName = $New
    $NewInstance.AdminNBName = "$($NewInstance.NBDomainName)\$New"

    #Set Admin Password
    If ($OldInstance.AdminPassword) {
        $Default = $OldInstance.AdminPassword
    }Else{
        $Default = "P@ssw0rd99"
    }
    Do {
        Write-Host 'Password for admin account?'
        $New = Read-Host "Between 10-20 characters, must be complex [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "(?=^.{10,20}$)((?=.*\d)(?=.*[A-Z])(?=.*[a-z])|(?=.*\d)(?=.*[^A-Za-z0-9])(?=.*[a-z])|(?=.*[^A-Za-z0-9])(?=.*[A-Z])(?=.*[a-z])|(?=.*\d)(?=.*[A-Z])(?=.*[^A-Za-z0-9]))^.*")
    $NewInstance.AdminPassword = $New

    #Set Domain Controller Name
    If ($OldInstance.DomainController) {
        $Default = $OldInstance.DomainController
    }Else{
        $Default = "DC1"
    }
    Do {
        $New = Read-Host "Domain Controller Name [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$")
    $NewInstance.DomainController = $New

    #Set Domain Controller IP
    If ($OldInstance.DomainControllerIP) {
        $Default = $OldInstance.DomainControllerIP
    }Else{
        $Default = "$($NewInstance.IPPrefix).50"
    }
    Do {
        $New = Read-Host "IP for Domain Controller $($NewInstance.DomainController)? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
    $NewInstance.DomainControllerIP = $New

    #Set Use DHCP
    If ($OldInstance.UseDHCP) {
        $Default = $OldInstance.UseDHCP
    }Else{
        $Default = "Y"
    }
    Do {
        $New = Read-Host "Use DHCP on network (Y/N) [$Default]"
        If (!($New)) {
            $New = $Default
        }Else {
            $New = $New.ToUpper()
        }
    }Until ($New -Match '[YN]')
    $NewInstance.UseDHCP = $New

    #Set DHCP Start
    If ($NewInstance.UseDHCP -eq 'Y') {
        If ($OldInstance.DHCPStart) {
            $Default = $OldInstance.DHCPStart
        }Else{
            $Default = "100"
        }
        Do {
            $New = Read-Host "Start DHCP at? [$Default]"
            If (!($New)) {
                $New = $Default
            }
        }Until (([Int]$New -gt '50') -and ([Int]$new -lt '254'))
        $NewInstance.DHCPStart = $New
    }

    #Set DHCP End
    If ($NewInstance.UseDHCP -eq 'Y') {
        If ($OldInstance.DHCPStop) {
            $Default = $OldInstance.DHCPStop
        }Else{
            $Default = "200"
        }
        Do {
            $New = Read-Host "Stop DHCP at? [$Default]"
            If (!($New)) {
                $New = $Default
            }
        }Until (([Int]$New -gt $NewInstance.DHCPStart) -and ([Int]$New -lt '255'))
        $NewInstance.DHCPStop = $New
    }

    Return $NewInstance
}


#Look for Server configuration
If (!($BeaterConfig = Read-BTRFromRegistry -Root 'HKLM:SOFTWARE\HobbyLobby\Beater')) {
    $BeaterConfig = @{}
    If (Read-Host "Unable to read existing config. Would you like to input basic configuration now?" -Eq "y") {
        If (Set-BTRServerConfigr -Config ([Ref]$BeaterConfig)) {
            If (Write-BTRToRegistry -Item $BeaterConfig -Root 'HKLM:SOFTWARE\HobbyLobby\Beater') {
                Write-BTRLog "Successfuly updated config" -Level Progress
            }Else{
                Write-BTRLog "Failed to write server config to registry" -Level Error
            }
        }Else{
            Write-BTRLog "Didn't finish server config." -Level Error
            Return
        }
    }
}

#Check and configure server
If (Configure-BTRServer -Config $BeaterConfig) {
    Write-BTRLog "Configured server!" -Level Progress
}Else{
    Write-BTRLog "Failed to configure server" -Level Error
}

#Check for Valid Instance
If (!($BeaterConfig.DefaultInstance)) {
    If (Read-Host "There is no default instance, would you like to create one? (y/n)" -eq "Y") {
        Set-BTRInstanceConfig -Config $BeaterConfig
    }
}
        
        


#Build Instance config

#Validate Instace

#Build Instance

#Check for Valid Base Image

#Build Base Image config

#Validate Base Image

#Build Base Image

#Main menu