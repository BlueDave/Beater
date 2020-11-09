

#Global Variables
$RegRoot = 'HKLM:SOFTWARE\HobbyLobby\Beater'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$LogLevel = 'Debug'
$ConsoleLevel = 'Debug'
$LogFile = "C:\WSUS\BeaterCommandLine.log"

$RootFolder = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
. "$RootFolder\BeaterFunction.ps1"


Function Get-BTRServerConfig {
    $NewConfig = @{}

    #Set Root Path
    $Default = "C:\Beater"
    Do {
        $New = Read-Host "Root Path? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewConfig.Rootpath = $New

    #Set Base Image Folder
    $Default = "$($NewConfig.Rootpath)\BaseImages"
    Do {
        $New = Read-Host "Path to Base Image Folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewConfig.BaseImagePath = $New

    #Set App Folder
    $Default = "$($NewConfig.Rootpath)\Apps"
    Do {
        $New = Read-Host "Path to App Folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewConfig.AppFolder = $New

    #Set Certificate Path
    $Default = "$($NewConfig.Rootpath)\Certificates"
    Do {
        $New = Read-Host "Path to certificate folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewConfig.CertFolder = $New

    #Set Working Folder
    $Default = "$($NewConfig.Rootpath)\Working"
    Do {
        $New = Read-Host "Path to working folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewConfig.WorkingFolder = $New

    Return $NewConfig
}

Function Get-BTRInstanceConfig {
     Param (
        [Parameter(Mandatory=$True)]$Config
    )

    $NewInstance = @{}

    #Set Name
    $OriginalDefault = "Beater"
    [Int]$Append = 1
    While($Config.Instances[$Default]) {
        $Default = "$OriginalDefault$Append"
        $Append++
    }
    Do {
        $New = Read-Host "Instance Name? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until (($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{3,15}$") -and (!($BeaterConfig.Instances[$New])))
    $NewInstance.Name = $New

    #Set AppFolder
    $Default = $Config.AppFolder
    Do {
        $New = Read-Host "Path to application install files? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.AppFolder = $New

    #Set Certificate Folder
    $Default = $Config.CertFolder
    Do {
        $New = Read-Host "Path to certificate folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.CertFolder = $New

    #Set Working Folder
    $Default = $Config.WorkingFolder
    Do {
        $New = Read-Host "Path to working folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.WorkingFolder = $New

    #Set VM Folder
    $Default = "$($Config.RootPath)\$($NewInstance.Name)\Virtual Machines"
    Do {
        $New = Read-Host "Path to VM Folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.VMPath = $New

    #Set HDD Folder
    $Default = "$($Config.RootPath)\$($NewInstance.Name)\Virtual Hard Disks"
    Do {
        $New = Read-Host "Path to HDD folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.HDDPath = $New

    #Set Snapshot Folder
    $Default = "$($Config.RootPath)\$($NewInstance.Name)\Snapshots"
    Do {
        $New = Read-Host "Path to snapshot folder? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.SnapShotPath = $New

    #Set VM Temp Folder
    $Default = "C:\Temp"
    Do {
        $New = Read-Host "Path to temp folder on VMs? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewInstance.VMTempFolder = $New

    #Set Use NAT
    $Default = "Y"
    Do {
        $New = Read-Host "Use NAT on switch (Y/N) [$Default]"
        If (!($New)) {
            $New = $Default
        }Else {
            $New = $New.ToUpper()
        }
    }Until ($New -Match '[YN]')
    If ($New -eq 'Y') {
        $NewInstance.UseNAT = $True
    }Else{
        $NewInstance.UseNAT = $False
    }

    #Set IP
    Do {
        $Default = "192.168.$(Get-Random -Minimum 2 -Maximum 254)"
    } Until ($Default -notin ($BeaterConfig.Instances.Values.IPPrefix))
    Do {
        $New = Read-Host "Network Address [$Default]"
        If (!($New)) {
            $New = $Default
        }ElseIf ($New.Substring($New.Length -2) -eq '.0') {
            $New = $New.Substring(0, $New.Length -2)
        }
    }Until ($New -Match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){2}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$" -and $New -notin ($BeaterConfig.Instances.Values.IPPrefix))
    $NewInstance.IPPrefix = $New

    #Set Subnet Mask and Subnet Mask Length
    $Default = "255.255.255.0"
    Do {
        $New = Read-Host "Subnet Mask [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ((($New.Split(".") | ForEach { ([Convert]::ToSTring($_,2)).PadLeft(8,'0') }) -join "").IndexOf('01') -eq -1)
    $NewInstance.SubnetMask = $New
    $Length = [RegEx]::Matches((($New.Split(".") | ForEach { ([Convert]::ToSTring($_,2)).PadLeft(8,'0') }) -join ""),'1').count
    $NewInstance.SubNetLength = $Length

    #Set Gateway
    $Default = "$($NewInstance.IPPrefix).1"
    Do {
        $New = Read-Host "Default Gateway [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
    $NewInstance.Gateway = $New

    #Set Switch Name
    $Default = "$($NewInstance.Name)"
    Do {
        $New = Read-Host "Name of Switch [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -notIn (Hyper-V\Get-VMSwitch | Select -ExpandProperty Name))
    $NewInstance.SwitchName = $New

    #Set Domain Name
    $Default = "$($NewInstance.Name).local"
    Do {
        $New = Read-Host "Name of Domain [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match “^((?!-))(xn--)?[a-z0-9][a-z0-9-_]{0,61}[a-z0-9]{0,1}\.(xn--)?([a-z0-9\-]{1,61}|[a-z0-9-]{1,30}\.[a-z]{2,})$”)
    $NewInstance.DomainName = $New

    #Set NB Domain Name
    $Default = $NewInstance.DomainName.Split('.')[0]
    Do {
        $New = Read-Host "NetBIOS Name of Domain [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$")
    $NewInstance.NBDomainName = $New

    #Set Admin Account Name
    $Default = "Administrator"
    Do {
        $New = Read-Host "Administrator account? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$")
    $NewInstance.AdminName = $New
    $NewInstance.AdminNBName = "$($NewInstance.NBDomainName)\$New"

    #Set Admin Password
    $Default = "P@ssw0rd99"
    Do {
        Write-Host 'Password for admin account?'
        $New = Read-Host "Between 10-20 characters, must be complex [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "(?=^.{10,20}$)((?=.*\d)(?=.*[A-Z])(?=.*[a-z])|(?=.*\d)(?=.*[^A-Za-z0-9])(?=.*[a-z])|(?=.*[^A-Za-z0-9])(?=.*[A-Z])(?=.*[a-z])|(?=.*\d)(?=.*[A-Z])(?=.*[^A-Za-z0-9]))^.*")
    $NewInstance.AdminPassword = $New

    #Set Domain Controller Name
    $VMs = Hyper-V\Get-VM | Select -ExpandProperty Name
    $OriginalDefault = "DC"
    [Int]$Append = 1
    Do {
        $Default = "$OriginalDefault$Append"
        $Append++
    }Until ($Default -notin $VMs)
    Do {
        $New = Read-Host "Domain Controller Name [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$" -and $New -notin $VMs)
    $NewInstance.DomainController = $New

    #Set Domain Controller IP
    $Default = "$($NewInstance.IPPrefix).50"
    Do {
        $New = Read-Host "IP for Domain Controller $($NewInstance.DomainController)? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
    $NewInstance.DomainControllerIP = $New

    #Set Use DHCP
    $Default = "Y"
    Do {
        $New = Read-Host "Use DHCP on network (Y/N) [$Default]"
        If (!($New)) {
            $New = $Default
        }Else {
            $New = $New.ToUpper()
        }
    }Until ($New -Match '[YN]')
    If ($New -eq 'Y') {
        $NewInstance.UseDHCP = $True
    }Else{
        $NewInstance.UseDHCP = $False
    }

    #Set DHCP Start
    If ($NewInstance.UseDHCP -eq 'Y') {
        $Default = "100"
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
        $Default = "200"
        Do {
            $New = Read-Host "Stop DHCP at? [$Default]"
            If (!($New)) {
                $New = $Default
            }
        }Until (([Int]$New -gt $NewInstance.DHCPStart) -and ([Int]$New -lt '255'))
        $NewInstance.DHCPStop = $New
    }

    #Set Time Zone
    $Default = "Central Standard Time"
    Do {
        $New = Read-Host "Time Zone? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until (Get-TimeZone -ListAvailable | Where Standardname -eq $New)
    $NewInstance.TimeZone = $New

    Return $NewInstance
}

Function Get-BTRBaseImageConfig {
     Param (
        [Parameter(Mandatory=$True)]$Config,
        [Parameter(Mandatory=$True)]$Instance
    )

    $NewBaseImage = @{}

    #Set OS Version
    Do {
        Write-Host "Please Select OS Version:"
        Write-Host "     1. Server 2019"
        Write-Host "     2. Server 2016"
        Write-Host "     3. Windows 10 LTSC 2019"
        $Choice = Read-Host "(1-3)"
    }Until ($Choice -ge 1 -and $Choice -le 3)
    Switch ($Choice) {
        1 {
            $NewBaseImage.Product = "Server2019"
            $DefautName = "Server2019"
            $DefaultKey = "N69G4-B89J2-4G8F4-WWYCC-J464C"
            $DefaultImageIndex = 2
            Break
        }2{
            $NewBaseImage.Product = "Server 2016"
            $DefautName = "Server2016"
            $DefaultKey = "WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY"
            $DefaultImageIndex = 2
            Break
        }3{
            $NewBaseImage.Product = "Win10LTSC2019"
            $DefautName = "LTSC2019"
            $DefaultKey = "M7XTQ-FN8P6-TTKYV-9D4CC-J462D"
            $DefaultImageIndex = 1
            Break
        }
    }

    #Set Name
    Do {
        $New = Read-Host "Base image name? [$DefautName]"
        If (!($New)) {
            $New = $DefautName
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{3,15}$")
    $NewBaseImage.Name = $New

    #Set file name
    $Default = "$($Config.BaseImagePath)\$($NewBaseImage.Name)-C.vhdx"
    Do {
        $New = Read-Host "Base image file name? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewBaseImage.BaseImage = $New

    #Set ISO Name
    $Default = "$($Instance.WorkingFolder)\$($NewBaseImage.Name)-Install.iso"
    Do {
        $New = Read-Host "Base image install ISO name? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+$")
    $NewBaseImage.CustomISO = $New

    #Set Update Source
    If ((Read-Host "Do you want to use a custom source for M$ updates? (Y/N) [Y]") -ne "N") {
        $Default = "https://HPWSUS01.hobbylobby.corp:8531"
        Do {
            $New = Read-Host "M$ update source? [$Default]"
            If (!($New)) {
                $New = $Default
            }
        }Until ($New -Match "(https?|[s]?)(:\/\/)([^\s,]+)")
        $NewBaseImage.UpdateSource = $New
    }

    #Chose File
    Write-Host "Please chose an install .ISO"
    [System.Reflection.Assembly]::LoadWithPartialName(“System.windows.forms”) | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $Instance.WorkingFolder
    $OpenFileDialog.filter = “Disk Image (*.iso)| *.iso”
    $OpenFileDialog.ShowDialog() | Out-Null
    $NewBaseImage.InstallMedia = $OpenFileDialog.filename

    #Set Product Key
    Do {
        $New = Read-Host "Product Key? [$DefaultKey]"
        If (!($New)) {
            $New = $DefaultKey
        }
    }Until ($New -Match "^[A-Z0-9]{4,8}(-[A-Z0-9]{4,8}){3,8}$")
    $NewBaseImage.ProductKey = $New

    #Set Base Image Index
    Do {
        $New = Read-Host "Image Index? [$DefaultImageIndex]"
        If (!($New)) {
            $New = $DefaultImageIndex
        }
    }Until ($New -ge 1 -and $New -le 6)
    $NewBaseImage.ImageIndex = $New

    #Set OSMD path
    $Default = $Config.OscdimgPath
    Do {
        $New = Read-Host "Path to oscdimg.exe? [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Like "*oscdimg.exe")
    $NewBaseImage.OscdimgPath = $New

    #Set Use DHCP
    #Set Use NAT
    $Default = "N"
    Do {
        $New = Read-Host "Use DHCP to configure base image? (Y/N) [$Default]"
        If (!($New)) {
            $New = $Default
        }Else {
            $New = $New.ToUpper()
        }
    }Until ($New -Match '[YN]')
    If ($New -eq 'Y') {
        $NewBaseImage.UseDHCP = $True
    }Else{
        $NewBaseImage.UseDHCP = $False
    }

    Return $NewBaseImage
}


Function Select-BTRInstance {
    Param (
        [Parameter(Mandatory=$True)]$Config
    )
    [Int]$Default = 1
    $Instances = $BeaterConfig.Instances.Values.Name
    Do {
        Write-Host "Select Instance"
        [Int]$I = 1
        ForEach ($Instance In $Instances) {
            Write-Host "   $I) $Instance"
            $I++
        }
        [Int]$New = Read-Host "   Choice? [$Default]"
        If (!($New)) {
            [Int]$New = $Default
        }
    }Until ($New -le $Instances.Count)
    Return $Instances[($New - 1)]
}

Return

#region ServerSetup
#Get/Set Server Config
If ($BeaterConfig = Read-BTRFromRegistry -Root $RegRoot) {
    Write-BTRLog "Found configuration information in registry at $RegRoot" -Level Debug
}Else{
    Write-BTRLog "Did not find server configuration information in registry at $RegRoot" -Level Debug
    If ((Read-Host "Unable to read existing server config. Would you like to configure server now? (Y/N)") -eq "y") {
        If ($BeaterConfig = Get-BTRServerConfig) {
            Write-BTRLog "Finished entering server config" -Level Debug
        }Else{
            Write-BTRLog "Didn't finish server config." -Level Error
            Return
        }
    }Else{
        Write-BTRLog "You must configure the server to continue" -Level Error
        Return
    }
}

#Check and configure server
If (Configure-BTRServer -Config $BeaterConfig) {
    Write-BTRLog "Configured server!" -Level Progress
}Else{
    Write-BTRLog "Failed to configure server" -Level Error
    Return
}

#Write Server Config to registry
If (!(Test-Path $RegRoot -ErrorAction SilentlyContinue)) {
    $Error.Clear()
    REG ADD $($RegRoot -replace ":","\") /f *>&1 | Out-Null
    If ($Error) {
        Write-BTRLog "Unable to create $RegRoot. Error: $($Error[0].Exception.Message)." -Level Error
    }Else{
        Write-BTRLog "Created $RegRoot." -Level Debug
    }
}
If (Write-BTRToRegistry -Item $BeaterConfig -Root $RegRoot) {
    Write-BTRLog "Successfully updated config" -Level Progress
}Else{
    Write-BTRLog "Failed to write server config to registry" -Level Error
    Return
}
#endregion

#region InstanceSetup
#Get/Set Default Instance configuration
If ($BeaterConfig.DefaultInstance) {
    Write-BTRLog "Default instance is $($BeaterConfig.DefaultInstance)" -Level Debug
}Else{
    If ($BeaterConfig.Instances) {
        If (Read-Host "There is no default instance, but there are instances defined, would you like to set a default? (y/n)" -eq "Y") {
            "Yea I haven't writen this yet.  Go fish."
            Return
        }Else{
            "You must define a default instance to continue"
            Return
        }
    }Else{
        If ((Read-Host "There are no instances.  Would you like to create one now? (y/n)") -eq "Y") {
            $NewInstance = Get-BTRInstanceConfig -Config $BeaterConfig
            $BeaterConfig.Add('Instances',@{})
            $BeaterConfig.DefaultInstance = $NewInstance.Name
            $BeaterConfig.Instances.Add($NewInstance.Name, $NewInstance)
        }Else{
            "You must have a default instance to continue."
            Return
        }
    }
}
        
#Validate or Build Default Instance
If (Configure-BTRInstance -Instance $BeaterConfig.Instances[$($BeaterConfig.DefaultInstance)]) {
    Write-BTRLog "Succesfully configured Default Instance $($BeaterConfig.DefaultInstance)!" -Level Progress
}Else{
    Write-BTRLog "Failed to configure Default Instance $($BeaterConfig.DefaultInstance)!" -Level Error
    Return
}

#Write Server Config to registry
If (Write-BTRToRegistry -Item $BeaterConfig -Root $RegRoot) {
    Write-BTRLog "Successfully updated config" -Level Progress
}Else{
    Write-BTRLog "Failed to write server config to registry" -Level Error
    Return
}
#endregion

#region BaseImage
#Get/Set Default Base Image
If ($BeaterConfig.Instances[$BeaterConfig.DefaultInstance].DefaultBaseImage) {
    Write-BTRLog "Base image settings looks good" -Level Debug
}Else{
    If ((Read-Host "Default Base image settings do not exist.  Would you like to configure a base image now? (Y/N)") -eq 'Y') {
        If ($NewBase = Get-BTRBaseImageConfig -Config $BeaterConfig -Instance $BeaterConfig.Instances[$BeaterConfig.DefaultInstance]) {
            If(!($BeaterConfig.BaseImages)) {
                $BeaterConfig.Add('BaseImages',@{})
            }
            $BeaterConfig.BaseImages.Add($NewBase.Name, $NewBase)
            $BeaterConfig.Instances[$BeaterConfig.DefaultInstance].DefaultBaseImage = $NewBase.Name
        }Else{
            Write-BTRLog "Failed to create default base image settings" -Level Error
            Return
        }
        #Write Server Config to registry
        If (Write-BTRToRegistry -Item $BeaterConfig -Root $RegRoot) {
            Write-BTRLog "Successfully updated config" -Level Progress
        }Else{
            Write-BTRLog "Failed to write server config to registry" -Level Error
            Return
        }
    }Else{
        Write-BTRLog "You must configure a base image to continue" -Level Error
        Return
    }
}


#Check for and create base image
$DefaultInstance = $BeaterConfig.Instances[$BeaterConfig.DefaultInstance]
$BaseImage = $BeaterConfig.BaseImages[$BeaterConfig.Instances[$BeaterConfig.DefaultInstance].DefaultBaseImage]
If (Test-Path -Path $BaseImage.BaseImage) {
    Write-BTRLog "Default base image exists at $($BaseImage.BaseImage)" -Level Debug
}Else{
    #Create ISO
    If ((Read-Host "Default base image install media does not exist.  Would you like to create an installer? (Y/N)") -eq 'N') {
        Write-BTRLog "You must create an install ISO to continue" -Level Error
        Return
    }Else{
        If (!(Test-Path -Path $BaseImage.CustomISO -ErrorAction SilentlyContinue)) {
            If (Create-BTRISO -Instance $DefaultInstance -BaseImage $BaseImage) {
                Write-BTRLog "Created ISO " -Level Progress
            }Else{
                Write-BTRLog "Failed to create ISO" -Level Error
                Return
            }
        }Else{
            Write-BTRLog "Base Image ISO Exists." -Level Debug
        } 
    }

    #Create base image
    If ((Read-Host "Default base image does not exist.  Would you like to create it now? (Y/N)") -eq 'N') {
        Write-BTRLog "You must create a base image to continue." -Level Error
        Return
    }Else{
        If (Create-BTRBaseVM -Instance $DefaultInstance -BaseImage $BaseImage) {
            Write-BTRLog "Base vm created. Waiting 5 seconds for VM to stabilize." -Level Progress
            Start-Sleep -Seconds 5
            Write-BTRLog "Starting VM" -Level Progress
            $Error.Clear()
            Hyper-V\Start-VM -VMName $BaseImage.Name -ErrorAction SilentlyContinue
            If ($Error) {
                Write-BTRLog "Unable to start VM $($BaseImage.Name). Error: $($Error[0].Exception.Message)." -Level Error
                Return
            }Else{
                Write-BTRLog "   Success" -Level Debug
            }

            #Wait for VM to come online
            If (!(Wait-BTRVMOnline -Instance $DefaultInstance -VMName $BaseImage.Name)) {
                Write-BTRLog "$($BaseImage.Name) never came online" -Level Error
                Return
            }

            #Configure Base VM
            Write-BTRLog "Configuring base image" -Level Progress
            If (Configure-BTRBaseImage -Instance $DefaultInstance -BaseImage $BaseImage) {
                Write-BTRLog "Configured base image" -Level Progress                
               
                Write-BTRLog "Waiting for updates to finish and VM to reboot" -Level Progress
                If (!(Wait-BTRVMOffline -Instance $DefaultInstance -VMName $BaseImage.Name)) {
                    Write-BTRLog "$($BaseImage.Name) isn't shutting down." -Level Error
                    Return
                }

                Write-BTRLog "Waiting for vm to finish reboot" -Level Progress
                If (!(Wait-BTRVMOnline -Instance $DefaultInstance -VMName $BaseImage.Name)) {
                    Write-BTRLog "$($BaseImage.Name) isn't comming up." -Level Error
                    Return
                } 
               
                #Prep Base image
                Write-BtrLog "Prepping base image" -level Progress
                If (Prep-BTRBaseImage -Instance $DefaultInstance -BaseImage $BaseImage) {
                    Write-BTRLog "Prepped base image" -Level Progress
                }Else{
                    Write-BTRLog "Failed to prep base image" -Level Error
                    Return
                }
            }Else{
                Write-BTRLog "Failed to configure base image" -Level Debug
                Return
            }
        }Else{
            Write-BTRLog "Failed to create base image" -Level Debug
            Return
        }
    }
}
#endregion


#region BuildDomain     
#Build Domain
If (Hyper-V\Get-VM -ErrorAction SilentlyContinue | Where Name -like $DefaultInstance.DomainController) {
    Write-BTRLog "Domain Controller for default instance exists." -Level Progress
}Else{
    $VMName = $DefaultInstance.DomainController
    If((Read-Host "You default instance lacks a domain controller.  Do you want to create it now? (Y/N)") -ne 'Y') {
        Write-BTRLog "You must have a DC to continue" -Level Error
        Return
    }

    Write-BTRLog "Creating $VMName" -Level Progress
    If (!(New-BTRVMFromTemplate -Instance $DefaultInstance -VmName $VMName -BaseImage $BaseImage)) {
        Write-BTRLog "Failed to make VM for DC" -Level Error
        Return
    }

    Start-Sleep 3

    Write-BTRLog "Writing Config to $VMName" -Level Progress
    If (!(Apply-BTRVMCustomConfig -VMName $VMName -Instance $DefaultInstance -IpAddress $DefaultInstance.DomainControllerIP -JoinDomain $False -BaseImage $BaseImage)) {
        Write-BTRLog "Failed to apply custom config to DC" -Level Error
        Return
    }

    Write-BTRLog "Staring $VMName" -Level Progress
    $Error.Clear()
    Hyper-V\Start-VM -VMName $VMName -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to power on DC" -Level Error
        Return
    }

    Write-BTRLog "Waiting for $VMName to finish building." -Level Progress
    If (!(Wait-BTRVMOnline -VMName $VMName -Instance $DefaultInstance)) {
        Write-BTRLog "DC never came online" -Level Error
        Return
    }

    Write-BTRLog "Doing post deploy tweaks on $VMName" -Level Progress
    If (!(Tweak-BTRVMPostDeloy -VMName $VMName -Instance $DefaultInstance)) {
        Write-BTRLog "Failed to apply post deploy tweaks." -Level Error
        Return
    }

    Write-BTRLog "Installing DC role on  $VMName." -Level Progress
    If (!(Install-BTRDomain -Instance $DefaultInstance)) {
        Write-BTRLog "Unable to isntall domain role." -Level Error
        Return
    }
           
    Write-BTRLog "Waiting for $VMName to reboot" -Level Progress
    If (!(Wait-BTRVMOffline -Instance $DefaultInstance -VMName $VMName)) {
        Write-BTRLog "$VMName isn't rebooting." -Level Error
        Return
    }
    If (!(Wait-BTRVMOnline -Instance $DefaultInstance -VMName $VMName)) {
        Write-BTRLog "$VMName isn't rebooting." -Level Error
        Return
    }

    Write-BTRLog "Configuring domain" -Level Progress
    If (!(Configure-BTRDomain -Instance $DefaultInstance)) {
        Write-BTRLog "Failed to configure domain on $VMName" -Level Error
        Return
    }

    Write-BTRLog "Configuring DHCP" -Level Progress
    If (!(SetUp-BTRDHCPServer -Instance $DefaultInstance)) {
        Write-BTRLog "Failed to configure domain on $VMName" -Level Error
        Return
    }    
}
#endregion

#Main menu
Write-Host "Your setup is good"

Do {
    Write-Host "What do you want to do now"
    Write-Host "1) Create New VM"
    Write-Host "2) Create New Instance"
    $Choice = Read-Host "Chose 1-2"
}Until (1 -le $Choice -le 2)

Switch ($Choice) {
    1 {
        $Instance = Select-BTRInstance -Config $BeaterConfig
        
        
        ##Figure hostname
        #$Default = ""
        #Do {
        #    $New = Read-Host "Domain Controller Name [$Default]"
        #    If (!($New)) {
        #        $New = $Default
        #    }
        #}Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$")
        #$HostName = $New
        #
        ##Get IP
        #$Default = Get-NextIP
        #Do {
        #    $New = Read-Host "IP for Domain Controller $($NewInstance.DomainController)? [$Default]"
        #    If (!($New)) {
        #        $New = $Default
        #    }
        #}Until ($New -Match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
        #$NewInstance.DomainControllerIP = $New
    }2{
        #Create new instance
        If ($NewInstance = Get-BTRInstanceConfig -Config $BeaterConfig) {
            $BeaterConfig.Instances.Add($NewInstance.Name, $NewInstance)
            If (Write-BTRToRegistry -Item $BeaterConfig -Root $RegRoot) {
                Write-BTRLog "Successfully updated config" -Level Progress
                If (Configure-BTRInstance -Instance $BeaterConfig.Instances[$NewInstance.Name]) {
                   Write-BTRLog "Created new instance $($NewInstance.Name)" -Level Progress
                }Else{
                    Write-BTRLog "Failed to create new instance $($NewInstance.Name)" -Level Error
                }
            }Else{
             Write-BTRLog "Failed to write server config to registry" -Level Error
            }
        }Else{
            Write-BTRLog "You didn't configure the instance fully"
        }
    }
}

    
