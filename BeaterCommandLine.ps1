

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

Function Get-cBTRInstanceConfig {
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

    If ((Read-Host "Do you want to configure a domain for $($NewInstance.Name) [Y]") -ne "Y") {
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

        
        If ($NewInstance.UseDHCP -eq 'Y') {
            #Set DHCP Start
            $Default = "100"
            Do {
                $New = Read-Host "Start DHCP at? [$Default]"
                If (!($New)) {
                    $New = $Default
                }
            }Until (([Int]$New -gt '50') -and ([Int]$new -lt '254'))
            $NewInstance.DHCPStart = $New

            #Set DHCP End
            $Default = "200"
            Do {
                $New = Read-Host "Stop DHCP at? [$Default]"
                If (!($New)) {
                    $New = $Default
                }
            }Until (([Int]$New -gt $NewInstance.DHCPStart) -and ([Int]$New -lt '255'))
            $NewInstance.DHCPStop = $New
        }
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

Function Get-cBTRBaseImageConfig {
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
    $BaseImages = $BeaterConfig.BaseImages.Values.Name
    Do {
        $New = Read-Host "Base image name? [$DefautName]"
        If (!($New)) {
            $New = $DefautName
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{3,15}$" -and $New -notin $BaseImages)
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


Function Select-cBTRInstance {
    Param (
        [Parameter(Mandatory=$True)]$Config
    )
    $Instances = $Config.Instances.Values.Name
    If ($Instances.Count -eq 0) {
        Return $False
    }ElseIf ($Instances.Count -eq 1) {
        Return $Instances
    }
    [Int]$Default = 1
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

Function Select-cBTRBaseImage {
    Param (
        [Parameter(Mandatory=$True)]$Config,
        [String]$Prompt = "Select BaseImage"
    )
    $BaseImages = $Config.BaseImages.Values.Name
    If ($BaseImages.Count -eq 0) {
        Return $False
    }ElseIf ($BaseImages.Count -eq 1) {
        Return $BaseImages
    }        
    [Int]$Default = 1
    Do {
        Write-Host $Prompt
        [Int]$I = 1
        ForEach ($BaseImage In $BaseImages) {
            Write-Host "   $I) $BaseImage"
            $I++
        }
        [Int]$New = Read-Host "   Choice? [$Default]"
        If (!($New)) {
            [Int]$New = $Default
        }
    }Until ($New -le $BaseImages.Count)
    Return $BaseImages[($New - 1)]
}

Function Select-cBTRVM {
    Param (
        [String]$Prompt,
        [String]$Confirm
    )
    $VMs =  Hyper-V\Get-VM | Where Notes -Like "*Instance*" | Select -ExpandProperty Name
    If ($VMs.Count -eq 0) {
        Write-BTRLog "No VMs eligible VMs found" -Level Error
        Return $False
    }ElseIf ($VMs.Count -eq 1) {
        $VMName = $VMs
    }Else{
        [Int]$Default = 1
        Do {
            Write-Host $Prompt
            [Int]$I = 1
            ForEach ($VM In $VMs) {
                Write-Host "   $I) $VM"
                $I++
            }
            [Int]$New = Read-Host "   Choice? [$Default]"
            If (!($New)) {
                [Int]$New = $Default
            }
        }Until ($New -le $VMs.Count)
        $VMName = $VMs[($New - 1)]
    }


    If ($Confirm) {
        If ((Read-Host "$Confirm $VMName.  Are you sure") -eq "Y") {
            Return $VMName
        }Else{
            Write-BTRLog "Aborted deleting $VMName"
            Return $False
        }
    }Else{
        Return $VMName
    }
 
}


Function New-cBTRVMFromTemplate {
Param (
        [Parameter(Mandatory=$True)]$Config
    )

    #Select Instance
    If (!($InstanceName = Select-cBTRInstance -Config $Config)) {
        Write-BTRLog "You must chose an instance" -Level Error
        Return $False
    }
    $Instance = $BeaterConfig.Instances[$InstanceName]

    #Select Base Image
    If (!($BaseImageName = Select-cBTRBaseImage -Config $Config)) {
        Write-BTRLog "You must chose an base image" -Level Error
        Return $False
    }
    $BaseImage = $BeaterConfig.BaseImages[$BaseImageName]

    #Select Name
    $VMs = Hyper-V\Get-VM | Select -ExpandProperty Name
    $OriginalDefault = "Guest"
    [Int]$Append = 1
    Do {
        $Default = "$OriginalDefault$Append"
        $Append++
    }Until ($Default -notin $VMs)
    Do {
        $New = Read-Host "VM Name [$Default]"
        If (!($New)) {
            $New = $Default
        }
    }Until ($New -Match "^(?![0-9]{1,15}$)[a-zA-Z0-9-]{1,15}$" -and $New -notin $VMs)
    $VMName = $New

    #Get IP Address
    If (!($Default = Get-BtrNextIP -Instance $Instance)) {
        $Default = "$($Instance.IPPrefix).100"
    }
    Do {
        $IPAddress = Read-Host "IP Address [$Default]"
        If (!($IPAddress)) {
            $IPAddress = $Default
        }
    }Until ($IPAddress -Match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")

    #Join Domain
    $Default = "Y"
    Do {
        $New = Read-Host "Join Domain (Y/N) [$Default]"
        If (!($New)) {
            $New = $Default
        }Else {
            $New = $New.ToUpper()
        }
    }Until ($New -Match '[YN]')
    If ($New -eq 'Y') {
        $JoinDomain = $True
    }Else{
        $JoinDomain = $False
    }

    #CPU count
    $Default = 3
    Do {
        $CPUCount = Read-Host "How many cores [$Default]"
        If (!($CPUCount)) {
            $CPUCount = $Default
        }
    }Until ($CPUCount -gt 0 -and $CPUCount -lt 6)

    #RAM
    [Int]$Default = 1
    Do {
        [Int]$MemoryGB = Read-Host "Gigs of RAM [$Default]"
        If (!($MemoryGB)) {
            $MemoryGB = $Default
        }
    }Until ($MemoryGB -gt 0 -and $MemoryGB -lt 17)

    #Create VM
    Write-BTRLog "Creating VM $VMName" -Level Debug
    Write-BTRLog "   Instance: $($Instance.Name)" -Level Debug
    Write-BTRLog "   BaseImage: $($BaseImage.Name)" -Level Debug
    Write-BTRLog "   CPUs: $CPUCount" -Level Debug
    Write-BTRLog "   GBs of RAM: $MemoryGB" -Level Debug
    If (New-BTRVMFromTemplate -Instance $Instance -BaseImage $BaseImage -VmName $VMName -CPUCount $CPUCount -MemoryGB $MemoryGB) {
        Write-BTRLog "   Success!" -Level Progress
    }Else{
        Write-BTRLog "Failed to create VM" -Level Error
        Return $False
    }

    #Update DNS
    If (Add-BtrDNSRecord -Instance $Instance -IPAddress $IPAddress -RecordName $VMName) {
        Write-BTRLog "Updated DNS record for $VMName" -Level Progress
    }Else{
        Write-BTRLog "Failed to update DNS for $VMName" -Level Error
        Return $False
    }

    #Configure VM
    If (Apply-BTRVMCustomConfig -Instance $Instance -BaseImage $BaseImage -VmName $VMName -IpAddress $IPAddress -JoinDomain $JoinDomain) {
        Write-BTRLog "Configured VM $VMName." -Level Progress
    }Else{
        Write-BTRLog "Failed to Configure VM" -Level Error
        Return $False
    }

    #Start VM
    Write-BTRLog "Staring $VMName" -Level Progress
    $Error.Clear()
    Hyper-V\Start-VM -VMName $VMName -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to power on $VMName" -Level Error
        Return $False
    }

    #Waiting for VM to build
    Write-BTRLog "Waiting for $VMName to finish building." -Level Progress
    If (!(Wait-BTRVMOnline -VMName $VMName -Instance $DefaultInstance)) {
        Write-BTRLog "$VMName never came online" -Level Error
        Return $False
    }

    Write-BTRLog "Doing post deploy tweaks on $VMName" -Level Progress
    If (!(Tweak-BTRVMPostDeloy -VMName $VMName -Instance $DefaultInstance -UseDomainCreds $JoinDomain)) {
        Write-BTRLog "Failed to apply post deploy tweaks to $VMName." -Level Error
        Return $False
    }

    Return $True
}

Function New-cBTRInstance {
    Param (
        [Parameter(Mandatory=$True)]$Config
    )

    #Get instance config from user
    If ($NewInstance = Get-cBTRInstanceConfig -Config $BeaterConfig) {
        Write-BTRLog "Instance $($NewInstance.Name) has been configured" -Level Progress
    }Else{
        Write-BTRLog "You didn't configure the instance fully" -Level Error
        Return $False
    }

    #Do the actual work to configure the instance
    If (Configure-BTRInstance -Instance $NewInstance) {
        Write-BTRLog "Created new instance $($NewInstance.Name)" -Level Progress
    }Else{
        Write-BTRLog "Failed to create new instance $($NewInstance.Name)." -Level Error
        Return $False
    }

    #If the instance is domain enabled, create the domain
    If ($NewInstance.DomainName) {

        #Make sure we have base images to work with, if not create one
        $BaseImages = $BeaterConfig.BaseImages.Values.Name
        If (!($BaseImages)) {
            If ((Read-Host "There aren't any base images.  Do you want to create one? [Y]") -ne "N") {
                If (New-cBTRBaseImage -Config $BeaterConfig -Instance $NewInstance ) {
                    Write-BTRLog "New Base Image created" -Level Progress
                }Else{
                    Write-BTRLog "Failed to create new Base Image" -Level Error
                    Return $False
                }
            }Else{
                Write-BTRLog "No base image, no domain. Failed to configure instance." -Level Error
                Return $False
            }
        }

        If (!($BaseImage = Select-cBTRBaseImage -Config $BeaterConfig -Prompt "Select Base image for DC")) {
            Write-BTRLog "You must select a base image to build a DC." -Level Error
            Return $False
        }

        If (!(New-cBTRDomain -Instance $NewInstance)) {
            Write-BTRLog "Failed to build domain." -Level Error
            Return $False
        }
    }
      
    #Write instance to registry
    $BeaterConfig.Instances.Add($NewInstance.Name, $NewInstance)
    If (Write-BTRToRegistry -Item $BeaterConfig -Root $RegRoot) {
        Write-BTRLog "Successfully wrote new instance to registry" -Level Progress
    }Else{
        Write-BTRLog "Failed to write new instance to registry. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }

    Return $True
}

Function New-cBTRDomain {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)]$BaseImage
    )

    $VMName = $Instance.DomainController

    If (Hyper-V\Get-VM -ErrorAction SilentlyContinue | Where Name -like $Instance.DomainController) {
        Write-BTRLog "Domain Controller for $($Instance.Name) instance alreadyexists." -Level Error
        Return $False
    }

    Write-BTRLog "Creating $VMName" -Level Progress
    If (!(New-BTRVMFromTemplate -Instance $DefaultInstance -VmName $VMName -BaseImage $BaseImage)) {
        Write-BTRLog "Failed to make VM $VMName" -Level Error
        Return $False
    }

    Write-BTRLog "Waiting 3 seconds for VM creation to finish" -Level Debug
    Start-Sleep 3

    Write-BTRLog "Writing Config to $VMName" -Level Progress
    If (!(Apply-BTRVMCustomConfig -VMName $VMName -Instance $Instance -IpAddress $Instance.DomainControllerIP -JoinDomain $False -BaseImage $BaseImage)) {
        Write-BTRLog "Failed to apply custom config to DC" -Level Error
        Return $False
    }

    Write-BTRLog "Staring $VMName" -Level Progress
    $Error.Clear()
    Hyper-V\Start-VM -VMName $VMName -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to power on $VMName" -Level Error
        Return $False
    }
    
    Write-BTRLog "Waiting for $VMName to finish building." -Level Progress
    If (!(Wait-BTRVMOnline -VMName $VMName -Instance $Instance)) {
        Write-BTRLog "$VMName never came online" -Level Error
        Return $False
    }
    
    Write-BTRLog "Doing post deploy tweaks on $VMName" -Level Progress
    If (!(Tweak-BTRVMPostDeloy -VMName $VMName -Instance $Instance)) {
        Write-BTRLog "Failed to apply post deploy tweaks." -Level Error
        Return $False
    }

    Write-BTRLog "Installing DC role on $VMName." -Level Progress
    If (!(Install-BTRDomain -Instance $Instance)) {
        Write-BTRLog "Unable to install domain role." -Level Error
        Return $False
    }
           
    Write-BTRLog "Waiting for $VMName to reboot (This always seems to take forever.)" -Level Progress
    If (!(Wait-BTRVMOffline -Instance $Instance -VMName $VMName -MaxWaitTime 15 )) {
        Write-BTRLog "$VMName isn't rebooting." -Level Error
        Return $False
    }
    If (!(Wait-BTRVMOnline -Instance $Instance -VMName $VMName -MaxWaitTime 15 -WaitForLogin)) {
        Write-BTRLog "$VMName isn't rebooting." -Level Error
        Return $False
    }

    Write-BTRLog "Configuring domain" -Level Progress
    If (!(Configure-BTRDomain -Instance $Instance)) {
        Write-BTRLog "Failed to configure domain on $VMName" -Level Error
        Return
    }
    
    If ($Instance.UseDHCP) {
        Write-BTRLog "Configuring DHCP" -Level Progress
        If (!(SetUp-BTRDHCPServer -Instance $Instance)) {
            Write-BTRLog "Failed to configure domain on $VMName" -Level Error
            Return
        }
    }   

}

Function New-cBTRBaseImage {
 Param (
        [Parameter(Mandatory=$True)][HashTable]$Config,
        [Parameter(Mandatory=$True)][HashTable]$Instance
    )

    #Get config from user
    If (!($NewBaseImage = Get-cBTRBaseImageConfig -Config $Config -Instance $Instance)) {
        Write-BTRLog "Failed to configure base image" -Level Error
        Return $False
    }

    #See if user wants to cusomize base image
    $Default = "N"
    Do {
        $New = Read-Host "Do you want to customize the base image before packing? (Y/N) [$Default]"
        If (!($New)) {
            $New = $Default
        }Else {
            $New = $New.ToUpper()
        }
    }Until ($New -Match '[YN]')
    If ($New -eq 'Y') {
        $CustomizeImage = $True
    }Else{
        $CustomizeImage = $False
    }

    #Create ISO
    If (Create-BTRISO -Instance $Instance -BaseImage $NewBaseImage) {
        Write-BTRLog "Created ISO " -Level Progress
    }Else{
        Write-BTRLog "Failed to create ISO" -Level Error
        Return $False
    }

    #Create VM for base image
    If (!(Create-BTRBaseVM -Instance $DefaultInstance -BaseImage $NewBaseImage)) {
        Write-BTRLog "Failed to create VM for $($NewBaseImage.Name)." -Level Error
        Return $False
    }

    Write-BTRLog "Base VM created. Waiting 5 seconds for VM to stabilize." -Level Progress
    Start-Sleep -Seconds 5

    Write-BTRLog "Starting VM" -Level Progress
    $Error.Clear()
    Hyper-V\Start-VM -VMName $NewBaseImage.Name -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to start VM $($NewBaseImage.Name). Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "   Success" -Level Debug
    }

    #Wait for VM to come online
    If (!(Wait-BTRVMOnline -Instance $Instance -VMName $NewBaseImage.Name)) {
        Write-BTRLog "$($BaseImage.Name) never came online" -Level Error
        Return $False
    }

    #Configure Base VM
    Write-BTRLog "Configuring base image" -Level Progress
    If (Configure-BTRBaseImage -Instance $Instance -BaseImage $NewBaseImage) {
        Write-BTRLog "Configured base image" -Level Progress
    }Else{
        Write-BTRLog "Failed to configure base image" -Level Error
        Return $False
    }
    
    #Wait for VM to update and reboot
    Write-BTRLog "Waiting for updates to finish and VM to reboot" -Level Progress
    If (!(Wait-BTRVMOffline -Instance $Instance -VMName $NewBaseImage.Name)) {
        Write-BTRLog "$($NewBaseImage.Name) isn't shutting down." -Level Error
        Return $False
    }
    Write-BTRLog "Waiting for vm to finish reboot" -Level Progress
    If (!(Wait-BTRVMOnline -Instance $Instance -VMName $NewBaseImage.Name)) {
        Write-BTRLog "$($NewBaseImage.Name) isn't comming up." -Level Error
        Return $False
    }

    #Pause for customization
    If ($CustomizeImage) {
        Write-Host "Base image deployement is done.  Go ahead and customize it."
        Read-Host "Hit any key to continue"
    }

    #Prep Base image
    Write-BtrLog "Prepping base image" -level Progress
    If (Prep-BTRBaseImage -Instance $Instance -BaseImage $NewBaseImage) {
        Write-BTRLog "Prepped base image" -Level Progress
    }Else{
        Write-BTRLog "Failed to prep base image" -Level Error
        Return $False
    }

    #Write BaseImage to registry
    $BeaterConfig.BaseImages.Add($NewBaseImage.Name, $NewBaseImage)
    If (Write-BTRToRegistry -Item $BeaterConfig -Root $RegRoot) {
        Write-BTRLog "Successfully wrote new Base Image to registry" -Level Progress
    }Else{
        Write-BTRLog "Failed to write new Base Image to registry. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }

    Return $True
}


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




Do {
    Write-Host "What do you want to do now"
    Write-Host "   1) Show Environment details"
    Write-Host "   2) Create VM"
    Write-Host "   3) Delete VM"
    Write-Host "   4) Create Instance"
    Write-Host "   5) Delete Instance"
    Write-Host "   6) Create BaseImage"
    Write-Host "   7) Delete BaseImage"
    Write-Host "   8) Exit"
    Switch (Read-Host "Chose 1-8") {
        1 {
            #Display Details
        }2{
            #Create new VM from template
            If (!(New-cBTRVMFromTemplate -Config $BeaterConfig)) {
                Write-BTRLog "Failed to create new VM" -Level Error
            }Else{
                Write-BTRLog "Created new VM" -Level Progress
            }
        }3{
            If ($VMToDelete = Select-cBTRVM -Prompt "Select VM to Delete" -Confirm "You've selected to delete") {
                Write-BTRLog "Deleting $VMToDelete" -Level Debug
                If (Delete-BTRVM -VmName $VMToDelete) {
                    Write-BTRLog "   Success!" -Level Debug
                }Else{
                    Write-BTRLog "Failed to delete $VMToDelete." -Level Error
                }
            }Else{
                Write-BTRLog "You must select something to delete" -Level Error
            }
        }4{
            #Create new instance
            If ($NewInstance = Get-cBTRInstanceConfig -Config $BeaterConfig) {
                If (Configure-BTRInstance -Instance $NewInstance) {
                    Write-BTRLog "Created new instance $($NewInstance.Name)" -Level Progress
                    $BeaterConfig.Instances.Add($NewInstance.Name, $NewInstance)
                    If (Write-BTRToRegistry -Item $BeaterConfig -Root $RegRoot) {
                        Write-BTRLog "Successfully wrote new instance to registry" -Level Progress
                    }Else{
                        Write-BTRLog "Failed to write new instance to registry. Error: $($Error[0].Exception.Message)." -Level Error
                    }
                }Else{
                    Write-BTRLog "Failed to create new instance $($NewInstance.Name). Error: $($Error[0].Exception.Message)." -Level Error
                }
            }Else{
                Write-BTRLog "You didn't configure the instance fully" -Level Error
            }
        }5{
            #Delete Instance
            $DeleteMe = Select-BTRInstance -Config $BeaterConfig
            If (Delete-BTRInstance -Instance $BeaterConfig.Instances[$DeleteMe] -DeleteVMs -DeleteFolders) {
                Write-BTRLog "Deleted Instance $DeleteMe" -Level Progress
                $BeaterConfig.Instances.Remove($DeleteMe)
                $Error.Clear()
                Remove-Item -Path "$RegRoot\Instances\$DeleteMe" -Recurse -Force -Confirm:$False -ErrorAction SilentlyContinue
                If ($Error) {
                    Write-BTRLog "Failed to remove instance $DeleteMe from registry. Error: $($Error[0].Exception.Message)." -Level Error
                    $Error.Clear()
                }Else{
                    Write-BTRLog "Completely removed $DeleteMe" -Level Progress
                }
            }Else{
                Write-BTRLog "Failed to Delete $DeleteMe" -Level Error
            }
        }6{
            #Create base image
            If ($Instance = Select-cBTRInstance -config $BeaterConfig ) {
                New-cBTRBaseImage -Config $BeaterConfig -Instance $BeaterConfig.Instances[$Instance]
            }Else{
                Write-BTRLog "You must select an instance to continue"
            }
        }7{
            #Delete base image
        }8{
            Return
        }
    }
} While ($True)

    
