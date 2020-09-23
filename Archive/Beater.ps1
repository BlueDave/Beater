$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$Debug = $True

#region Stucts
$2019BaseImage = @{
    Name = 'Server2019'
    BaseImage = 'C:\WSUS\BaseImages\Server2019-C.vhdx'
    InstallMedia = 'C:\Users\dkbluem1\Downloads\SW_DVD9_Win_Server_STD_CORE_2019_64Bit_English_DC_STD_MLF_X21-96581.ISO'
    CustomISO = 'C:\WSUS\Working\Server2019-Install.ISO'
    WorkingPath = 'C:\WSUS\Working'
    OscdimgPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    ProductKey = 'N69G4-B89J2-4G8F4-WWYCC-J464C'
    AdminName = 'Administrator'
    AdminPassword = 'P@ssw0rd99'
    SwitchName = "Beater"
    UseDHCP = $True
    TempIP = '192.168.116.201'
    Gateway = '192.168.116.1'
    SubnetLength = "24"
    TimeZone = "Central Standard Time"
    CertFolder = 'C:\WSUS\Certificates'
    AppFolder = 'C:\WSUS\Apps'
    UseWSUS = $True
    UpdateSource = 'https://HPWSUS01.hobbylobby.corp:8531'
    DisableAutoUpdates = $True
    OptimizeDotNet = $False
    WorkingFolder = 'C:\WSUS\Working'
    VMTempFolder = 'C:\Temp'
}

$2016BaseImage = @{
    Name = 'Server2016'
    BaseImage = 'C:\WSUS\BaseImages\Server2016-C.vhdx'
    InstallMedia = 'C:\Users\dkbluem1\Downloads\SW_DVD9_Win_Svr_STD_Core_and_DataCtr_Core_2016_64Bit_English_-2_MLF_X21-22843.ISO'
    CustomISO = 'C:\WSUS\Working\Server2016-Install.ISO'
    WorkingPath = 'C:\WSUS\Working'
    OscdimgPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    ProductKey = 'WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY'
    AdminName = 'Administrator'
    AdminPassword = 'P@ssw0rd99'
    SwitchName = "Beater"
    UseDHCP = $True
    TempIP = '192.168.116.201'
    Gateway = '192.168.116.1'
    SubnetLength = "24"
    TimeZone = "Central Standard Time"
    CertFolder = 'C:\WSUS\Certificates'
    AppFolder = 'C:\WSUS\Apps'
    UseWSUS = $True
    UpdateSource = 'https://HPWSUS01.hobbylobby.corp:8531'
    DisableAutoUpdates = $True
    OptimizeDotNet = $False
    WorkingFolder = 'C:\WSUS\Working'
    VMTempFolder = 'C:\Temp'
}

$BeaterInstance = @{
    Host = "LHL315574"
    Name = "Beater"
    DomainName = "Beater.Local"
    NBDomainName = "Beater"
    IPPrefix = "192.168.116"
    Gateway = "192.168.116.1"
    SubnetMask = "255.255.255.0"
    SubnetLength = "24"
    UseDHCP = $True
    DHCPStart = 100
    DHCPStop = 200
    AdminName = 'Administrator'
    AdminNBName = "Beater\Administrator"
    AdminPassword = 'P@ssw0rd99'
    DomainController = 'DC1'
    DomainControllerIP = "192.168.116.50"
    RootPath = "C:\WSUS\"
    HDDPath = "C:\WSUS\Virtual Hard Disks"
    VMPath = "C:\WSUS\Virtual Machines"
    SnapshotPath = "C:\WSUS\Snapshots"
    WorkingFolder = 'C:\WSUS\Working'
    VMTempFolder = 'C:\Temp'
    SwitchName = "Beater"
    UseNAT = $True
}

#endregion

#region Generics
Function Write-BTRLog {
    Param (
        [Parameter(Mandatory=$True)][String]$Entry
    )
    Write-Host $Entry
}

Function Write-BTRError {
    Param (
        [Parameter(Mandatory=$True)][String]$Entry
    )
    Write-Host "Error:$Entry"
    Read-Host "Hit Enter to exit"
    Return
}

Function Wait-BTRVMOnline {
    Param (
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)]$Instance,
        [int64]$MaxWaitTime = 600,
        [int64]$Interval = 1
    )

    #Figure out credentials
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    #Make sure VM Exists and is on
    If (!(Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return 1
    }

    $StartTime = Get-Date
    Do {
        If (($(Get-Date) - $StartTime).TotalSeconds -ge $MaxWaitTime) {
            Return 2
        }
        Start-Sleep $Interval
    }Until (Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {dir c:\} -ErrorAction SilentlyContinue | Out-Null )
    Return $False
}

Function Install-BTRSofware {
    Param (
        [String]$Name,
        $Instance,
        $BaseImage,
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)][String]$Installer,
        [String]$WebLink,
        [String]$Args,
        [Bool]$IsDomainJoined = $True
        
    )

    If (!($Instance -or $BaseImage)) {
        Read-Host "You must provide either a Base Image or an Instance"
        Return
    }

    If ($Instance -and $BaseImage) {
        Read-Host "You can not specify both a base image and an instance"
        Return
    }

    If ($Instance) {
        If ($IsDomainJoined) {
            $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
            $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)
        }Else{
            $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
            $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminName,$SecurePassword)
        }
        $HostPath = $Instance.WorkingFolder
        $HostFullPath = "$HostPath`\$Installer"
        $VMPath = $Instance.VMTempFolder
        $VMFullpath = "$VMPath`\$Installer"
    }Else{
        $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
        $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)
    }

    If (!($Name)) {
        $Name = $Installer
    }
    "Installing $Name"
    
    #Make sure destination folder exists
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        If (!(Test-Path $Using:VmPath)) {
            New-Item -Path $Using:VmPath -ItemType Directory -Force -Confirm:$False
        }
    }

    #If the file doesn't exit on the VM, copy over or download installer
    If (!(Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {Test-Path $Using:VMFullPath})) {
        If (Test-Path $HostFullPath) {
            $Error.Clear()
            Copy-VMFile -VMName $VMName -SourcePath $HostFullPath -DestinationPath $VMFullpath -FileSource Host
            If ($Error) {
                Read-Host "Can't copy $Name to VM"
                Return
            }
        }Else{
            If (!($WebLink)) {
                Read-Host "If the installer isn't on the host, you must provide a download URL"
                Return
            }Else{
                $Error.Clear()
                Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
                    Invoke-WebRequest -Uri $ -OutFile $Using:VMFullPath -ErrorAction SilentlyContinue
                }
                If ($Error) {
                    Read-Host "Can't download $Name"
                    Return
                }
            }
        }
    }
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Start-Process $Using:VMFullpath -ArgumentList $Using:Args  -Wait -NoNewWindow
    }
    If ($Error) {
        Read-Host "Install failed"
        Return
    }
}
#endregion

#region setup
Function Install-BTREnvironment {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )

    #Install Hyper-V if it's not enabled
    If ($(Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
        Write-BTRError "Installed Hyper-V.  You must now reboot to continue"
        Exit
    }

    #Create folders if they don't exist
    If (!(Test-Path $($Instance.RootPath))) {
        New-Item $($Instance.RootPath) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $($Instance.VMPath))) {
        New-Item $($Instance.VMPath) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $($Instance.HDDPath))) {
        New-Item $($Instance.HDDPath) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $Instance.SnapshotPath)) {
        New-Item $Instance.SnapshotPath -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }

    #Create Network Switch
    If (!(Hyper-V\Get-VMSwitch | Where Name -eq $Instance.SwitchName)) {
        If ($Instance.UseNAT) {
            $Error.Clear()
            Hyper-V\New-VMSwitch -SwitchName $Instance.SwitchName -SwitchType Internal -ComputerName $Instance.Host
            If ($Error) {
                Write-BTRError "Can't create new switch"
            }
        }Else{
            $Error.Clear()
            Hyper-V\New-VMSwitch -SwitchName $Instance.SwitchName -SwitchType Private -ComputerName $Instance.Host
            If ($Error) {
                Write-BTRError "Can't create new switch"
            }
        }
    }

    #Set IP on host NIC
    If ($Instance.UseNAT) {
        If (!(Get-NetAdapter | Where name -Like "*$($Instance.SwitchName)*" | Get-NetIPAddress | Where IPAddress -like $Instance.Gateway)) {
            If (!($Index = Get-NetAdapter | Where name -Like "*$($Instance.SwitchName)*" | Select -ExpandProperty ifIndex)) {
                Write-BTRError "Can't find instance switch"
            }
            $Error.Clear
            New-NetIPAddress -IPAddress $Instance.Gateway -PrefixLength $Instance.SubnetLength -InterfaceIndex $Index
            $Error.Clear()
            If ((!(Get-NetAdapter | Where name -Like "*$($Instance.SwitchName)*" | Select -ExpandProperty ifIndex))) {
                Write-BTRError "Can't set IP on instance switch"
            }
        }
    }

    #Set subnet as Private
    Get-NetConnectionProfile | Where InterfaceAlias -Like "*$($Instance.SwitchName)*" | Set-NetConnectionProfile -NetworkCategory Private

    #Setup NAT
    If ($Instance.UseNAT) {
        If (!(Get-NetNat | Where InternalIPInterfaceAddressPrefix -eq "$($Instance.IPPrefix).0/$($Instance.SubnetLength)")) {
            $Error.Clear()
            New-NetNat -Name "$($Instance.SwitchName)NAT" -InternalIPInterfaceAddressPrefix "$($Instance.IPPrefix).0/$($Instance.SubnetLength)"
            If ($Error) {
                Write-BTRError "Can't create NAT"
            }
        }
    }
}

Function Install-BRTADK {
    Param (
        [Parameter(Mandatory=$True)]$BaseImage
    )

    If (Test-Path $BaseImage.OscdimgPath) {
        "OSCDIMG already installed!"
    }Else{
        $InstallFile = "$($BaseImage.WorkingPath)\adksetup.exe"
        If (!(Test-Path $InstallFile)) {
            #Get Windows Version
            $WinVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId

            "Getting ADK installer"
            If ($Winver -eq 1903) {
                Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/?linkid=2086042 -OutFile $InstallFile -ErrorAction SilentlyContinue
            } ElseIf ($WinVer -eq 1809) {
                Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/?linkid=2026036 -OutFile $InstallFile -ErrorAction SilentlyContinue
            } ElseIf ($Winver -eq 1803) {
                Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/?linkid=873065 -OutFile $InstallFile -ErrorAction SilentlyContinue  
            } ElseIf ($Winver -eq 1709) {
                Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/p/?linkid=859206 -OutFile $InstallFile -ErrorAction SilentlyContinue 
            } Else{
                "I don't know how to get an installer for Windows 10 $WinVer."
                "Go download the correct vesion of adksetup.exe to $($BaseImage.WorkingPath)"
                "Then run the script again"
            }
        }

        If (Test-Path $InstallFile) {
            "Installing adk"
            Start-Process "$InstallFile" -ArgumentList "/quiet /features OptionId.DeploymentTools" -Wait -NoNewWindow
        }Else{
            "Unable to download ADK.  Good luck, you're on your own."
        }

        If (!(Test-Path $InstallFile)) {
            "Failed to install ADK.   Good luck, you're on your own."
        }
    }

}

Function Create-BTRISO {
    Param (
        [Parameter(Mandatory=$True)]$BaseImage
    )    

   If (!(Test-Path $BaseImage.InstallMedia)) {
       "$($BaseImage.InstallMedia) dosn't exist"
       Return
   }
   
   If (!(Test-Path $BaseImage.WorkingPath)) {
       "$($BaseImage.WorkingPath) dosn't exist"
       Return
   }
   
   $ExtractFolder = "$($BaseImage.WorkingPath)\ISO"
   
   If (Test-Path $ExtractFolder) {
        Remove-Item -Path "$ExtractFolder\*" -Force -Confirm:$False -Recurse
   }Else{
        New-Item -Path $ExtractFolder -ItemType Directory -Force -Confirm:$False
   } 
   
   "Mounting $($BaseImage.InstallMedia)"
   Mount-DiskImage -ImagePath $BaseImage.InstallMedia 
   $DriveLetter = (Get-DiskImage -ImagePath $BaseImage.InstallMedia | Get-Volume).DriveLetter
   
   "Copying files from $($BaseImage.InstallMedia) to $ExtractFolder"
   xcopy "$DriveLetter`:\*" "$ExtractFolder\*" /o /h /y /e > $null
   
   "Dismounting $($BaseImage.InstallMedia)"
   Dismount-DiskImage -ImagePath $BaseImage.InstallMedia
   
   "Renaming boot files"
   Rename-Item -Path "$ExtractFolder\efi\microsoft\boot\cdboot.efi" -NewName cdboot-prompt.efi
   Rename-Item -Path "$ExtractFolder\efi\microsoft\boot\cdboot_noprompt.efi" -NewName cdboot.efi
   Rename-Item -Path "$ExtractFolder\efi\microsoft\boot\efisys.bin" -NewName efisys_prompt.bin
   Rename-Item -Path "$ExtractFolder\efi\microsoft\boot\efisys_noprompt.bin" -NewName efisys.bin
   
   "Deleting bootfix.bin"
   Remove-Item -Path "$ExtractFolder\boot\bootfix.bin" -Force -Confirm:$False

    "Creating autounattend.xml"
    $UnattendContent = '<?xml version="1.0" encoding="utf-8"?>
    <unattend xmlns="urn:schemas-microsoft-com:unattend">
        <settings pass="windowsPE">
            <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <SetupUILanguage>
                    <UILanguage>en-US</UILanguage>
                </SetupUILanguage>
                <InputLocale>0c09:00000409</InputLocale>
                <SystemLocale>en-US</SystemLocale>
                <UILanguage>en-US</UILanguage>
                <UILanguageFallback>en-US</UILanguageFallback>
                <UserLocale>en-US</UserLocale>
            </component>
            <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <DiskConfiguration>
                    <WillShowUI>OnError</WillShowUI>
                    <DisableEncryptedDiskProvisioning>true</DisableEncryptedDiskProvisioning>
                    <Disk wcm:action="add">
                        <CreatePartitions>
                            <CreatePartition wcm:action="add">
                                <Order>1</Order>
                                <Size>500</Size>
                                <Type>Primary</Type>
                            </CreatePartition>
                            <CreatePartition wcm:action="add">
                                <Order>2</Order>
                                <Size>100</Size>
                                <Type>EFI</Type>
                            </CreatePartition>
                            <CreatePartition wcm:action="add">
                                <Order>3</Order>
                                <Size>128</Size>
                                <Type>MSR</Type>
                            </CreatePartition>
                            <CreatePartition wcm:action="add">
                                <Extend>true</Extend>
                                <Order>4</Order>
                                <Type>Primary</Type>
                            </CreatePartition>
                        </CreatePartitions>
                        <ModifyPartitions>
                            <ModifyPartition wcm:action="add">
                                <Order>2</Order>
                                <PartitionID>2</PartitionID>
                                <Label>System</Label>
                                <Format>FAT32</Format>
                            </ModifyPartition>
                            <ModifyPartition wcm:action="add">
                                <Order>3</Order>
                                <PartitionID>3</PartitionID>
                            </ModifyPartition>
                            <ModifyPartition wcm:action="add">
                                <Format>NTFS</Format>
                                <Label>Windows</Label>
                                <Letter>C</Letter>
                                <Order>4</Order>
                                <PartitionID>4</PartitionID>
                            </ModifyPartition>
                            <ModifyPartition wcm:action="add">
                                <PartitionID>1</PartitionID>
                                <TypeID>de94bba4-06d1-4d40-a16a-bfd50179d6ac</TypeID>
                                <Order>1</Order>
                                <Format>NTFS</Format>
                            </ModifyPartition>
                        </ModifyPartitions>
                        <DiskID>0</DiskID>
                        <WillWipeDisk>true</WillWipeDisk>
                    </Disk>
                </DiskConfiguration>
                <Display>
                    <HorizontalResolution>1024</HorizontalResolution>
                    <VerticalResolution>768</VerticalResolution>
                </Display>
                <ImageInstall>
                    <OSImage>
                        <InstallFrom>
                            <MetaData wcm:action="add">
                                <Key>/IMAGE/INDEX</Key>
                                <Value>2</Value>
                            </MetaData>
                        </InstallFrom>
                        <InstallTo>
                            <DiskID>0</DiskID>
                            <PartitionID>4</PartitionID>
                        </InstallTo>
                        <InstallToAvailablePartition>false</InstallToAvailablePartition>
                        <WillShowUI>OnError</WillShowUI>
                    </OSImage>
                </ImageInstall>
                <UserData>
                    <ProductKey>
                        <WillShowUI>OnError</WillShowUI>
                        <Key>' + $BaseImage.ProductKey + '</Key>
                    </ProductKey>
                    <AcceptEula>true</AcceptEula>
                    <FullName>Administrator</FullName>
                    <Organization>Me, Myself, and I</Organization>
                </UserData>
                <EnableFirewall>false</EnableFirewall>
            </component>
        </settings>
        <settings pass="generalize">
            <component name="Microsoft-Windows-Security-SPP" processorArchitecture="wow64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <SkipRearm>1</SkipRearm>
            </component>
        </settings>
        <settings pass="specialize">
            <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <InputLocale>0409:00000409</InputLocale>
                <SystemLocale>en-US</SystemLocale>
                <UILanguage>en-US</UILanguage>
                <UILanguageFallback>en-US</UILanguageFallback>
                <UserLocale>en-US</UserLocale>
            </component>
            <component name="Microsoft-Windows-Security-SPP-UX" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <SkipAutoActivation>true</SkipAutoActivation>
            </component>
            <component name="Microsoft-Windows-SQMApi" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <CEIPEnabled>0</CEIPEnabled>
            </component>
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <ComputerName>' + $BaseImage.Name + '</ComputerName>
                <DisableAutoDaylightTimeSet>false</DisableAutoDaylightTimeSet>
                <ProductKey>' + $BaseImage.ProductKey + '</ProductKey>
                <RegisteredOrganization>Me, Myself, and I</RegisteredOrganization>
                <RegisteredOwner>Administrator</RegisteredOwner>
                <ShowWindowsLive>false</ShowWindowsLive>
                <TimeZone>Central Standard Time</TimeZone>
            </component>
        </settings>
        <settings pass="oobeSystem">
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <OOBE>
                    <HideEULAPage>true</HideEULAPage>
                    <HideLocalAccountScreen>true</HideLocalAccountScreen>
                    <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                    <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                    <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                    <NetworkLocation>Work</NetworkLocation>
                    <SkipMachineOOBE>true</SkipMachineOOBE>
                    <SkipUserOOBE>true</SkipUserOOBE>
                    <ProtectYourPC>3</ProtectYourPC>
                </OOBE>
                <UserAccounts>
                    <AdministratorPassword>
                        <Value>' + $BaseImage.AdminPassword + '</Value>
                        <PlainText>true</PlainText>
                    </AdministratorPassword>
                </UserAccounts>
            </component>
        </settings>
    </unattend>'


    $UnattendContent > "$ExtractFolder\autounattend.xml"

    If (Test-Path $BaseImage.CustomISO) {
        Remove-Item $BaseImage.CustomISO -Force -Confirm:$False
    }

    "Writing $($BaseImage.CustomISO)"
    & $BaseImage.OscdimgPath -m -o -u2 -udfver102 -bootdata:2#p0,e,b"$ExtractFolder\boot\etfsboot.com"#pEF,e,b"$ExtractFolder\efi\microsoft\boot\efisys.bin" "$ExtractFolder" $BaseImage.CustomISO

    "Cleaning up"
    Remove-Item -Path "$ExtractFolder" -Force -Confirm:$False -Recurse
}

Function Create-BaseVM {
    Param (
        [Parameter(Mandatory=$True)]$BaseImage
    )    

    $VMName = $BaseImage.Name
    
    If (Hyper-V\Get-VM | Where Name -EQ $VMName) {
        "$VMName already exists"
        Return
    }

    $VM = Hyper-V\New-VM -Name $VMName -MemoryStartupBytes 1024MB -Generation 2
    Hyper-V\Set-VM -Name $VMName -ProcessorCount 3 -AutomaticCheckpointsEnabled:$False -Confirm:$False -CheckpointType Production
    Hyper-V\Connect-VMNetworkAdapter -VMName $VMName -SwitchName $BaseImage.SwitchName
    Hyper-V\Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"
    Hyper-V\New-VHD -Path $BaseImage.BaseImage -Dynamic -SizeBytes 40GB
    Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $BaseImage.BaseImage
    Hyper-V\Add-VMDvdDrive -VMName $VMName -Path $BaseImage.CustomISO
    $DVDDrive = Hyper-V\Get-VMDvdDrive -VMName $VMName
    $BootHDD = Hyper-V\Get-VMHardDiskDrive -VMName $VMName
    Hyper-V\Set-VMFirmware -VMName $VMName -EnableSecureBoot Off -BootOrder $DVDDrive, $BootHDD

    #Required to issue MAC Address
    Hyper-V\Start-VM -Name $VMName
    Start-Sleep -Seconds 3
    Hyper-V\Stop-VM -Name $VMName -TurnOff -Force -Confirm:$False
}

Function Configure-BTRBaseImage {
    Param (
        [Parameter(Mandatory=$True)]$BaseImage
    )

    #Make sure VM exists
    $VMName = $BaseImage.Name
    If (!(Hyper-V\Get-VM | Where Name -EQ $VMName)) {
        "$VMName does not exist"
        Return
    }

    #Figure out credentials
    $SecurePassword = ConvertTo-SecureString -AsPlainText $BaseImage.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($BaseImage.AdminName,$SecurePassword)

    #Get host DNS servers
    $DNSServers = Get-DnsClientServerAddress | Where AddressFamily -eq 2 | Where ServerAddresses | Select -ExpandProperty ServerAddresses
    $MacAddress = $(Hyper-V\Get-VMNetworkAdapter -VMName $VMName | Select -ExpandProperty MACAddress) -replace "([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])", '$1$2-$3$4-$5$6-$7$8-$9$10-$11$12'
    If ($MacAddress.Length -ne 17) {
        "Unable to get Mac address"
        Read-Host "Hit Enter to exit"
        Return
    }
    
    #Set static IP
    If (!($BaseImage.UseDHCP)) {
        "Setting IP to $($BaseImage.TempIP)"
        Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock { 
            $IfIndex = Get-NetAdapter | WHERE MacAddress -eq $Using:MacAddress | Select -ExpandProperty ifIndex
            New-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -IPAddress $Using:BaseImage.TempIP -PrefixLength $Using:BaseImage.SubnetLength -DefaultGateway $Using:BaseImage.Gateway
            Get-NetAdapter | foreach { Disable-NetAdapterBinding -InterfaceAlias $_.Name -ComponentID ms_tcpip6 }
            Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $Using:DNSServers
            Set-DnsClient -InterfaceIndex $IfIndex -RegisterThisConnectionsAddress $False
        }
    }
    
    "Disabling IE Enhanced Security"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
        $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
        Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
        Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    }

    "Enabling RDP"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
        (Get-WmiObject -class Win32_TSGeneralSetting -Namespace root\cimv2\terminalservices -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(1)
    }

    #SetTimeZone
    "Setting Time Zone"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Set-TimeZone -Id $Using:BaseImage.TimeZone
    }

    #Optional components
    "Installing Optional Components"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Install-WindowsFeature -IncludeAllSubFeature RSAT
        Install-WindowsFeature -IncludeAllSubFeature GPMC
        Add-WindowsCapability -Online -Name NetFx3~~~~ -Source D:\Sources\sxs
        Enable-WindowsOptionalFeature -Online -FeatureName TFTP -NoRestart
        Enable-WindowsOptionalFeature -Online -FeatureName TelnetClient -NoRestart
    }

    #Install Certificates
    "Installing Certficates"
    $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate
    ForEach ($Certificate In (Get-ChildItem $BaseImage.CertFolder)) {
        $DestinationPath = "C:\Temp\$($Certificate.Name)"
        $Cert.Import($Certificate.FullName)
        Copy-VMFile $VMName -SourcePath $Certificate.FullName -DestinationPath $DestinationPath -CreateFullPath -FileSource Host -Force
        If ($Cert.Issuer -eq $Cert.GetName()) {
            Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
                Import-Certificate -Filepath $Using:DestinationPath -CertStoreLocation "Cert:\LocalMachine\Root"
            }
        }Else{
            Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
                Import-Certificate -Filepath $Using:DestinationPath -CertStoreLocation "Cert:\LocalMachine\CA"
            }
        }
    }

    #Install Apps
    "Copying apps over"
    ForEach ($File In Get-ChildItem $BaseImage.AppFolder) {
        Copy-VMFile $VMName -SourcePath $File.FullName -DestinationPath "C:\Temp\$($File.Name)" -CreateFullPath -FileSource Host -Force
    }
    
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        "Installing Chrome"
        If (Test-Path "C:\Temp\GoogleChromeStandaloneEnterprise64.msi") {
            Start-Process Msiexec.exe -ArgumentList '/i "C:\Temp\GoogleChromeStandaloneEnterprise64.msi" /qb!' -Wait
            Unregister-ScheduledTask -TaskName "GoogleUpdateTaskMachineCore" -Confirm:$False
            Unregister-ScheduledTask -TaskName "GoogleUpdateTaskMachineUA" -Confirm:$False
            REG ADD HKLM\Software\Policies\Google\Chrome /v HardwareAccelerationModeEnabled /d 1 /t REG_DWORD /f
        }
    
        "Installing NotePad++"
        If (Test-Path "C:\Temp\npp.*.Installer.exe") {
            Start-Process -FilePath "C:\Temp\npp.*.Installer.exe" -ArgumentList "/S" -Wait -NoNewWindow
	        Rename-Item -Path "C:\Program Files (x86)\Notepad++\updater" -NewName "updater_disabled" -Force -Confirm:$False
        }
        
        "Installing 7Zip"
        If (Test-Path "C:\Temp\7z*.exe") {
            Start-Process -FilePath "C:\Temp\7z*.exe" -ArgumentList "/S" -Wait -NoNewWindow
        }
        
        "Installing Putty"
        If (Test-Path "C:\Temp\Putty-*-Installer.msi") {
            "Putty found"
            $PuttyFile = Get-Item "C:\Temp\Putty-*-Installer.msi"
            Start-Process Msiexec.exe -ArgumentList "/i $PuttyFile /qb!" -Wait -NoNewWindow
        }
    
        "Installing WinSCP"
        If (Test-Path "C:\Temp\WinSCP-*-Setup.exe") {
            Start-Process -FilePath "C:\Temp\WinSCP-*-Setup.exe" -ArgumentList "/Silent /Norestart /ALLUSERS" -Wait -NoNewWindow
	        Remove-Item "C:\Users\Public\Desktop\WinSCP.lnk" -Force -Confirm:$False
        }
    
        "Creating IE Shortucts"
        $Shell = New-Object -ComObject Wscript.Shell
	    $Shortcut = $Shell.CreateShortcut("C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Internet Explorer.lnk")
	    $Shortcut.TargetPath = "C:\Program Files\internet explorer\iexplore.exe"
	    $Shortcut.WorkingDirectory = "%HOMEDRIVE%%HOMEPATH%"
	    $Shortcut.Description = "Finds and displays information and Web sites on the Internet."
	    $Shortcut.Save()
    
        "Creating RDP shortcut"
        $Shell = New-Object -ComObject Wscript.Shell
	    $Shortcut = $Shell.CreateShortcut("C:\Users\Public\Desktop\Remote Desktop Connection.lnk")
	    $Shortcut.TargetPath = "%windir%\system32\mstsc.exe"
	    $Shortcut.WorkingDirectory = "%windir%\system32\"
	    $Shortcut.Description = "Use your computer to connect to a computer that is located elsewhere and run programs or access files."
	    $Shortcut.Save()
    }
    
    
    If ($BaseImage.UseWSUS) {
        "Configuring Updates"
        Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
            REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate /v TargetGroup /d SVDI /t REG_SZ /f
            REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate /v TargetGroupEnabled /d 1 /t REG_DWORD /f
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name WUServer -Value $Using:BaseImage.UpdateSource -Force -Confirm:$False
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name WUStatusServer -Value $Using:BaseImage.UpdateSource -Force -Confirm:$False
            REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU /v UseWUServer /d 1 /t REG_DWORD /f 
        }
    }

    "Installing Windows Update Module"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
       Install-PackageProvider -Name NuGet -Confirm:$False -Force
       Register-PSRepository -Name "PSGallery" –SourceLocation "https://www.powershellgallery.com/api/v2/" -InstallationPolicy Trusted -Confirm:$False -Force
       Install-Module -Name PSWindowsUpdate -Confirm:$False -Force
    }

    "Checking for updates"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Get-WindowsUpdate
    }

    "Installing updates"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Install-WindowsUpdate -AcceptAll –AutoReboot
    }

}

Function Prep-BTRBaseImage {
    Param (
        [Parameter(Mandatory=$True)]$BaseImage
    )

    #Make sure VM exists
    $VMName = $BaseImage.Name
    If (!(Hyper-V\Get-VM | Where Name -EQ $VMName)) {
        "$VMName does not exist"
        Return
    }

    #Figure out creditials
    $SecurePassword = ConvertTo-SecureString -AsPlainText $BaseImage.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($BaseImage.AdminName,$SecurePassword)

    #Machine Clean Up
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock { 
        
        If ($Using:BaseImage.OptimizeDotNet) {
            "Optimizing .Net"
	        Start-Process $Env:WINDIR\microsoft.net\framework64\v4.0.30319\ngen.exe -ArgumentList "executequeueditems /force" -Wait
	        Start-Process $Env:WINDIR\microsoft.net\framework64\v4.0.30319\ngen.exe -ArgumentList "update /force" -Wait
        }
        
        If ($Using:BaseImage.DisableAutoUpdates) {
            "Disabling Auto Update"
	        Stop-Service -Name BITS
	        Stop-Service -Name wuauserv
	        Set-Service -Name BITS -StartupType Disabled -ErrorAction SilentlyContinue
	        Set-Service -Name wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
            takeown /F C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator /A /R
            icacls C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator /grant Administrators:F /T
            Get-ScheduledTask -TaskPath "\Microsoft\Windows\UpdateOrchestrator\*" | Disable-ScheduledTask
            Get-ScheduledTask -TaskPath "\Microsoft\Windows\WindowsUpdate\*" | Disable-ScheduledTask
            Remove-Item C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator\* -Force -Confirm:$False -Recurse
            REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate /v WUServer /d https://localhost:8531 /t REG_SZ /f
        }


        "Cleaning up junk"
        Remove-Item "C:\Temp" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue #2> $null
        Remove-Item "C:\Windows\Temp\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Users\Administrator\Downloads\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Users\Administrator\Documents\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Users\Administrator\AppData\Local\Temp\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Prefetch\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Logs\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue

        #Empty Recycling Bin
        Clear-RecycleBin -Force -Confirm:$False


	    "Deleting shadow copies"
	    Set-Service VSS -StartupType Manual
	    Start-Service VSS
	    Start-Process VSSAdmin.exe -ArgumentList "Delete Shadows /All /Quiet" -Wait
	    Stop-Service VSS
	    Set-Service VSS -StartupType Disabled
        
        "Purging all event logs"
	    Get-WinEvent -ListLog * -Force -ErrorAction SilentlyContinue | % { Wevtutil.exe cl $_.logname } 2> .\%LOCALAPPDATA%
        
        "Defraging C:"
	    Optimize-Volume -DriveLetter C -Defrag

        "Running Sysprep"
        C:\Windows\System32\Sysprep\sysprep.exe /oobe /generalize /mode:vm /shutdown /quiet
    }
    
    #Delete VM and leave disk
    "Waiting for VM to shutdown"
    $VM = Hyper-V\Get-VM -VMName $VMName
    Do {
        Start-Sleep 5
    } Until ($VM.State -eq "Off")
    "Deleting VM"
    Hyper-V\Remove-VM -Name $VMName -Force -Confirm:$False
    "Optimizing vhd"
    Optimize-VHD -Path $BaseImage.BaseImage -Mode Full
    "Setting vhd to Read Only"
    Set-ItemProperty -Path $BaseImage.BaseImage -Name IsReadOnly -Value $True

    #Deleting $($BaseImage.CustomISO)
    "Deleting Install ISO"
    Remove-Item $BaseImage.CustomISO -Force -Confirm:$False
}

Function Install-BTRDomain {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    #Install Domain role
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Install-WindowsFeature -Name AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools -Confirm:$False
    }
    If ($IsBroken) {
        "Unable to install Domain role"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Configure Domain
    $DomainName = $Instance.DomainName
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Install-ADDSForest -DomainMode 7 -ForestMode 7 -Force -DomainName $Using:Instance.DomainName -SafeModeAdministratorPassword $Using:SecurePassword -DomainNetbiosName $Using:Instance.NBDomainName
    }
    If ($IsBroken) {
        "Unable to create domain"
        Read-Host "Hit Enter to exit"
        Return
    }
}

Function Configure-BTRDomain {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    $DNSServers = Get-DnsClientServerAddress | Where AddressFamily -eq 2 | Where ServerAddresses | Select -First 1 | Select -ExpandProperty ServerAddresses

    #Create Reverse Lookup Zone
    $NetworkID = "$($Instance.IPPrefix).0/$($Instance.SubnetLength)"
    $Octets = $Instance.IPPrefix -split "\."
    $ZoneName = $Octets[2] + "." + $Octets[1] + "." + $Octets[0] + ".in-addr.arpa"
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        If (!(Get-DnsServerZone | Where ZoneName -like $Using:ZoneName)) {
            Add-DNSServerPrimaryZone -NetworkID $Using:NetworkID -ReplicationScope Forest -DynamicUpdate Secure  -Confirm:$False
        }
    }
    If ($IsBroken) {
        "Unable to create reverse lookup zone"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Setup Forwarders
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Set-DnsServerForwarder -UseRootHint $False -IPAddress $Using:DNSServers -EnableReordering $True -Confirm:$False
    }
    If ($IsBroken) {
        "Unable to set DNS forwarders"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Remove root hints
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Get-DnsServerRootHint | Remove-DnsServerRootHint -Confirm: $False -Force
    }
    If ($IsBroken) {
        "Unable to remove root hints"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Set Aging/Scavanging
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Set-DnsServerScavenging -ScavengingState $True -RefreshInterval 7.00:00:00 -NoRefreshInterval 7.00:00:00 -ApplyOnAllZones
    }
    If ($IsBroken) {
        "Unable to set scavanging"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Register DC in Reverse lookup zone
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        IPConfig /registerDNS
    }
    If ($IsBroken) {
        "Unable to register DC in DNS"
        Read-Host "Hit Enter to exit"
        Return
    }
}

Function SetUp-BTRDHCPServer {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    #Install DHCP role
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Install-WindowsFeature -Name DHCP -IncludeAllSubFeature -IncludeManagementTools -Confirm:$False
    }
    If ($IsBroken) {
        "Unable to install DHCP role"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Authorize DHCP in Domain
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Add-DhcpServerInDC -DNSName $Using:Instance.DomainController -IPAddress $Using:Instance.DomainControllerIP
    }
    If ($IsBroken) {
        "Unable to Authorize DHCP in Domain"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Configure IPv4 options
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Set-DhcpServerSetting -ConflictDetectionAttempts 1
        Set-DhcpServerv4DnsSetting -DynamicUpdates "Always" -DeleteDnsRRonLeaseExpiry $True
    }
    If ($IsBroken) {
        "Unable to configure IPv4 options in DHCP"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Create Scope
    $Start = $Instance.IPPrefix + "." + $Instance.DHCPStart
    $End = $Instance.IPPrefix + "." + $Instance.DHCPStop
    $ScopeID = $Instance.IPPrefix + ".0"
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ErrorVariable $IsBroken -ScriptBlock {
        Add-DhcpServerv4Scope -Name $Using:Instance.Name -StartRange $Using:Start -EndRange $Using:End -SubnetMask $Using:Instance.SubnetMask -State Active -LeaseDuration "1.0:00:00" 
        Set-DhcpServerv4OptionValue -ScopeId $Using:ScopeID -DNSServer $Using:Instance.DomainControllerIP -DNSDomain $Using:Instance.DomainName -Router $Using:Instance.Gateway
    }
    If ($IsBroken) {
        "Unable to configure IPv4 options in DHCP"
        Read-Host "Hit Enter to exit"
        Return
    }
}
#endregion

#region DeployVM
Function New-BTRVMFromTemplate {
     Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$VmName,
        [Parameter(Mandatory=$True)]$BaseImage,
        [Int]$CPUCount = 3,
        [Int64]$MemoryMB,
        [Int64]$MemoryGB
    ) 

    If ($MemoryGB) {
        [Int64]$Memory = $MemoryGB * 1024 * 1024 * 1024
    }ElseIf ($MemoryMB) {
        [Int64]$Memory = $MemoryMB * 1024 * 1024
    }Else {
        [Int64]$Memory =  1024 * 1024 * 1024
    }
    
    $HDDName = "$($Instance.HDDPath)\$VMName-C.vhdx"

    If (!(Test-Path $BaseImage.BaseImage)) {
        "Base Image $($BaseImage.BaseImage) does not exist!"
        Read-Host "Hit Enter to exit"
        Return
    }

    If (Test-Path $HDDName) {
        "$HDDName already exists!"
        Read-Host "Hit Enter to exit"
        Return
    }

    "Cloning $($BaseImage.BaseImage) to $HDDName"
    $Error.Clear()
    $HDD = Hyper-V\New-VHD -ComputerName $Instance.Host -ParentPath $BaseImage.BaseImage -Path $HDDName -Differencing
    If ($Error) {
        "Unable to create HDD"
        Read-Host "Hit Enter to exit"
        Return
    }
    
    $Error.Clear()
    "Creating VM $VMName"
    $VM = Hyper-V\New-VM -Name $VMName -ComputerName $Instance.Host -Generation 2 -VHDPath $HDDName -Path $Instance.VMPath
    If ($Error) {
        "Unable to create VM"
        Read-Host "Hit Enter to exit"
        Return
    }
    
    "Configuring $VMName"
    Hyper-V\Set-VM -Name $VMName -ComputerName $Instance.Host -ProcessorCount $CPUCount -AutomaticCheckpointsEnabled:$False -CheckpointType Production -Confirm:$False -SnapshotFileLocation $Instance.SnapShotPath
    Hyper-V\Set-VMMemory -VMName $VMName -ComputerName $Instance.Host -DynamicMemoryEnabled $True -MinimumBytes $Memory
    Hyper-V\Connect-VMNetworkAdapter -VMName $VMName -ComputerName $Instance.Host -SwitchName $Instance.SwitchName
    Hyper-V\Enable-VMIntegrationService -VMName $VMName -ComputerName $Instance.Host -Name "Guest Service Interface"
    Hyper-V\Set-VMFirmware -VMName $VMName -ComputerName $Instance.Host -EnableSecureBoot Off

    "Power cycling $VMName (Required to issue MAC address.)"
    Hyper-V\Start-VM -Name $VMName -ComputerName $Instance.Host
    Start-Sleep -Seconds 3
    Hyper-V\Stop-VM -Name $VMName -ComputerName $Instance.Host -TurnOff -Force -Confirm:$False 
}
    
Function Get-NextIP {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    ) 
    
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    $IP = Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        Get-DnsServerResourceRecord -ZoneName $using:Instance.DomainName | Where RecordType -EQ 'A' | Select -ExpandProperty RecordData | Select -ExpandProperty IPv4Address | Select -ExpandProperty IPAddressToString | Sort | Select -Last 1
    }
    $Octets = $IP -split "\."
    $Octets[3] = [String]([Int]$Octets[3] + 1)
    $IP = $Octets -join "."
    Return $IP
}

Function Add-BtrDNSRecord {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$RecordName,
        [Parameter(Mandatory=$True)][String]$IPAddress
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    "Adding $RecordName to DNS"
    $Error.Clear()
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        Add-DnsServerResourceRecordA -ZoneName $Using:Instance.DomainName -Name $Using:RecordName -IPv4Address $Using:IPAddress -CreatePtr
    }
    If ($Error) {
        "Unable to set static IP in DNS"
        Read-Host "Hit key to continue"
        Return
    }
}

Function Apply-BTRVMCustomConfig {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)][String]$IpAddress,
        [Parameter(Mandatory=$True)]$BaseImage,
        [Bool]$JoinDomain = $True
    )

    $MacAddress = $(Hyper-V\Get-VMNetworkAdapter -VMName $VMname -ComputerName $Instance.Host | Select -ExpandProperty MACAddress) -replace "([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])", '$1$2-$3$4-$5$6-$7$8-$9$10-$11$12'
    If ($MacAddress.Length -ne 17) {
        "Unable to retrive Mac address"
        Read-Host "Hit Enter to exit"
        Return
    }

    $HDDName = "$($Instance.HDDPath)\$VMName-C.vhdx"

    "Mounting $HDDName"
    $Error.Clear()
    $DriveLetter = Mount-VHD -Path $HDDName -Passthru | Get-Partition | Where DriveLetter | Select -ExpandProperty DriveLetter
    If ($Error) {
        "Unable to mount $HDDName"
        Read-Host "Hit Enter to exit"
        Return
    }

    "Writing config file for $VMName"
    $ConfigFile = $DriveLetter + ":\Windows\Panther\unattend.xml"

    $FileContent = '
    <?xml version="1.0" encoding="utf-8"?>
    <unattend xmlns="urn:schemas-microsoft-com:unattend">
    	<settings pass="specialize">
    		<component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    			<InputLocale>0409:00000409</InputLocale>
    			<SystemLocale>en-US</SystemLocale>
    			<UILanguage>en-US</UILanguage>
    			<UILanguageFallback>en-US</UILanguageFallback>
    			<UserLocale>en-US</UserLocale>
    		</component>
    		<component name="Microsoft-Windows-Security-SPP-UX" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    			<SkipAutoActivation>true</SkipAutoActivation>
    		</component>
    		<component name="Microsoft-Windows-SQMApi" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    			<CEIPEnabled>0</CEIPEnabled>
    		</component>
    		<component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    			<ComputerName>' + $VMName + '</ComputerName>
    			<ProductKey>' + $BaseImage.ProductKey + '</ProductKey>
    		</component>
    		<component name="Microsoft-Windows-TCPIP" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    			<Interfaces>
    				<Interface wcm:action="add">
    					<Identifier>' + $MacAddress + '</Identifier>
    					<Ipv4Settings>
    						<DhcpEnabled>false</DhcpEnabled> 
    						<Metric>20</Metric> 
    						<RouterDiscoveryEnabled>false</RouterDiscoveryEnabled> 
    					</Ipv4Settings>
    					<UnicastIpAddresses>
    						<IpAddress wcm:action="add" wcm:keyValue="1">' + $IpAddress + '/' + $Instance.SubnetLength + '</IpAddress>
    					</UnicastIpAddresses>
    					<Routes>
    						<Route wcm:action="add">
    							<Identifier>1</Identifier> 
    							<Metric>10</Metric> 
    							<NextHopAddress>' + $Instance.Gateway + '</NextHopAddress> 
    							<Prefix>0.0.0.0/0</Prefix> 
    						</Route>
    					</Routes>
    				</Interface>
    			</Interfaces>
    		</component>
    		<component name="Microsoft-Windows-DNS-Client" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    			<Interfaces>
    				<Interface wcm:action="add">
    					<Identifier>' + $MacAddress + '</Identifier>
    					<DNSDomain>' + $Instance.DomainName + '</DNSDomain>
    					<DNSServerSearchOrder>
    						<IpAddress wcm:action="add" wcm:keyValue="1">' + $Instance.DomainControllerIP + '</IpAddress>
    					</DNSServerSearchOrder>
    					<EnableAdapterDomainNameRegistration>false</EnableAdapterDomainNameRegistration>
    					<DisableDynamicUpdate>true</DisableDynamicUpdate>
    				</Interface>
    			</Interfaces>
    		</component>'

        If ($JoinDomain) {
            $FileContent += '
            <component name="Microsoft-Windows-UnattendedJoin" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <Identification>
                    <Credentials>
                        <Domain>' + $Instance.DomainName + '</Domain>
                        <Password>' + $Instance.AdminPassword + '</Password>
                        <Username>' + $instance.AdminName + '</Username>
                    </Credentials>
                    <JoinDomain>' + $Instance.DomainName + '</JoinDomain>
                </Identification>
            </component>'
        }
        
        $FileContent += '
    	</settings>
    	<settings pass="oobeSystem">
    		<component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    			<AutoLogon>
    				<Password>
    					<Value>' + $Instance.AdminPassword + '</Value>
    					<PlainText>true</PlainText>
    				</Password>'
                If ($JoinDomain) {
                    $FileContent += '
                    <Domain>' + $Instance.DomainName + '</Domain>'
                }
                $FileContent += '
    				<Enabled>true</Enabled>
    				<Username>' + $instance.AdminName + '</Username>
    			</AutoLogon>
    			<OOBE>
    				<HideEULAPage>true</HideEULAPage>
    				<HideLocalAccountScreen>true</HideLocalAccountScreen>
    				<HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
    				<HideOnlineAccountScreens>true</HideOnlineAccountScreens>
    				<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
    				<NetworkLocation>Work</NetworkLocation>
    				<ProtectYourPC>3</ProtectYourPC>
    				<SkipMachineOOBE>true</SkipMachineOOBE>
    				<SkipUserOOBE>true</SkipUserOOBE>
    			</OOBE>
    			<RegisteredOrganization>Me, Myself, and I</RegisteredOrganization>
    			<RegisteredOwner>Owner</RegisteredOwner>
    			<DisableAutoDaylightTimeSet>false</DisableAutoDaylightTimeSet>
    			<TimeZone>Central Standard Time</TimeZone>
    			<UserAccounts>
    				<AdministratorPassword>
    					<Value>' + $Instance.AdminPassword + '</Value>
    					<PlainText>true</PlainText>
    				</AdministratorPassword>
    			</UserAccounts>
    		</component>
    	</settings>
    </unattend>'
    
    
    $FileContent > $ConfigFile
    
    "Dismounting $HDDName"
    $Error.Clear()
    Dismount-VHD -Path $HDDName
    If ($Error) {
        "Unable to dismount $HDDName"
        Read-Host "Hit Enter to exit"
        Return
    }
}

Function Tweak-BTRVMPostDeloy {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$VMName
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    #Disable IPv6
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock { 
        Get-NetAdapter | foreach { Disable-NetAdapterBinding -InterfaceAlias $_.Name -ComponentID ms_tcpip6 }
    }

    #Disable Server Manager
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask
    }
}
#endregion

#region InstallApps
Function Install-BTRExchange {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)][String]$ExchangeISO,
        [String]$PrereqPath,
        [Int64]$StoreSizeGB = 100,
        [Int64]$LogSizeGB = 50
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    #Make sure ISO exists
    If (!(Test-Path $ExchangeISO)) {
        Read-Host "Can't find $ExchangeISO!"
        Return
    }

    #Make sure VM Exists and is on
    If (!(Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return
    }ElseIf(!(Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {dir c:\})) {
        Read-Host "Unable to connect to $VMName"
        Return
    }

    ##Make sure there isn't already Exchange in the domain
    #If (Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {Get-AdGroup "Exchange Servers" -ErrorAction SilentlyContinue 2>&1 | Out-Null}) {
    #    Read-Host "Looks like you already have an exchange organiztion in $($Instance.Name)"
    #    Return
    #}

    #"Creating M: Drive"
    #$Path = "$($Instance.HDDPath)\$VMName-M.vhdx"
    #Hyper-V\New-VHD -Path $Path -SizeBytes 100GB -Dynamic
    #Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $Path
    #Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
    #    Get-Disk | Where PartitionStyle -eq RAW  | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize -DriveLetter M
    #    Format-Volume -DriveLetter M -FileSystem NTFS -NewFileSystemLabel "MailStore" -Confirm:$False -Force
    #}
    #
    #"Creating L: Drive"
    #$Path = "$($Instance.HDDPath)\$VMName-L.vhdx"
    #Hyper-V\New-VHD -Path $Path -SizeBytes 50GB -Dynamic
    #Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $Path
    #Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
    #    Get-Disk | Where PartitionStyle -eq RAW | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize -DriveLetter L
    #    Format-Volume -DriveLetter L -FileSystem NTFS -NewFileSystemLabel "MailLog" -Confirm:$False -Force
    #}

    #Install-BTRSofware -Name ".net 4.8" -Instance $Instance -VMName $VMName -WebLink https://go.microsoft.com/fwlink/?linkid=208863 -Installer "ndp48-x86-x64-allos-enu.exe" -Args "/q /norestart"

    #Install-BTRSofware -Name "Unified Communications Managed API 4.0 Runtime" -Instance $BeaterInstance -VMName Ex1 -WebLink "https://download.microsoft.com/download/2/C/4/2C47A5C1-A1F3-4843-B9FE-84C0032C61EC/UcmaRuntimeSetup.exe" -Installer "UcmaRuntimeSetup.exe" -Args "/passive /norestart"

    #Install-BTRSofware -Name "Visual C++ Redistributable Packages for Visual Studio 2013" -Instance $BeaterInstance -VMName Ex1 -WebLink "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe" -Installer "vcredist_x64.exe" -Args "/passive /norestart"


    #"Mounting EXchange ISO ($ExchangeISO)"
    #Hyper-V\Add-VMDvdDrive -VMName $VMName -Path $ExchangeISO
    
        

}

Function Install-BTRSQL {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)][String]$SQLISO,
        [Int64]$DatabaseSizeGB = 100,
        [Int64]$LogSizeGB = 50,
        [String]$SQLUser = "SQLUser"
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    #Make sure ISO exists
    If (!(Test-Path $SQLISO)) {
        Read-Host "Can't find $SQLISO!"
        Return
    }

    #Make sure VM Exists and is on
    If (!(Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return
    }ElseIf(!(Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {dir c:\})) {
        Read-Host "Unable to connect to $VMName"
        Return
    }

    If (!(Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock { Test-Path "S:\" -ErrorAction SilentlyContinue })) {
        "Creating S: Drive"
        $Path = "$($Instance.HDDPath)\$VMName-S.vhdx"
        $Size = $DatabaseSizeGB * 1024 * 1024 * 1024
        Hyper-V\New-VHD -Path $Path -SizeBytes $Size -Dynamic
        Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $Path
        Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
            Get-Disk | Where PartitionStyle -eq RAW  | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize -DriveLetter S
            Format-Volume -DriveLetter S -FileSystem NTFS -NewFileSystemLabel "Databases" -Confirm:$False -Force
        }
    }
    
    If (!(Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock { Test-Path "L:\" -ErrorAction SilentlyContinue })) {
        "Creating L: Drive"
        $Path = "$($Instance.HDDPath)\$VMName-L.vhdx"
        $Size = $LogSizeGB * 1024 * 1024 * 1024
        Hyper-V\New-VHD -Path $Path -SizeBytes $Size -Dynamic
        Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $Path
        Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
            Get-Disk | Where PartitionStyle -eq RAW | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize -DriveLetter L
            Format-Volume -DriveLetter L -FileSystem NTFS -NewFileSystemLabel "Logs" -Confirm:$False -Force
        }
    }

    If (!(Get-VM -Name $VMName | Get-VMDvdDrive | Where Path -Like $SQLISO)) {
        "Mounting SQL ISO ($SQLISO)"
        Hyper-V\Add-VMDvdDrive -VMName $VMName -Path $SQLISO -ErrorAction SilentlyContinue
    }

    "Creating Service Account"
    $UPN = "$SQLUser@$($Instance.DomainName)"
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        If (!(Get-ADUser -Filter * | Where SamAccountName -eq $Using:SQLUser)) {
            $SecurePassword = ConvertTo-SecureString -AsPlainText $Using:Instance.AdminPassword -Force
            New-AdUser -Name "SQL Service Account" -SamAccountName $Using:SQLUser -UserPrincipalName $Using:UPN -DisplayName "SQL Service Account" -AccountPassword $SecurePassword -ChangePasswordAtLogon $False -Confirm:$False -PasswordNeverExpires $True -Enabled $True
        }
    }

    "Making $SQLUser a Local Admin on $VMname"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        If (!(Get-LocalGroupMember Administrators | Where Name -like "*$Using:SQLUser")) {
            Add-LocalGroupMember -Group Administrators -Member $Using:UPN
        }
    }

    $Args =  '/Q /ACTION="install" /INDICATEPROGRESS="True" /UpdateEnabled="False" /ERRORREPORTING="False" '
    $Args += '/IACCEPTSQLSERVERLICENSETERMS /SUPPRESSPRIVACYSTATEMENTNOTICE /IACCEPTPYTHONLICENSETERMS /IACCEPTROPENLICENSETERMS '
    $Args += '/FEATURES=SQLENGINE,CONN,SDK,SNAC_SDK /INSTANCENAME=MSSQLSERVER '
    $Args += '/SQLBACKUPDIR="C:\Backup" /SQLUSERDBDIR="S:\Database" /SQLUSERDBLOGDIR="L:\Logs" '
    $Args += '/ADDCURRENTUSERASSQLADMIN="False" /SQLSYSADMINACCOUNTS="' + $Instance.NBDomainName + '\Domain Admins" /SQLSYSADMINACCOUNTS="BUILTIN\Administrators" '
    $Args += '/SECURITYMODE="SQL" /SAPWD="' + $Instance.AdminPassword + '" '
    $Args += '/SQLSVCACCOUNT="' + $Instance.NBDomainName + '\' + $SQLUser + '" /SQLSVCPASSWORD="' + $Instance.AdminPassword + '" '

    "Installing SQL Server"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Start-Process "D:\setup.exe" -ArgumentList $Using:Args -Wait 
    }

    "Configuring Firewall"
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        $FWRules = Get-NetFirewallRule
        If (!($FWRules | Where DisplayName -Like “SQL Server”)) {
            New-NetFirewallRule -DisplayName “SQL Server” -Direction Inbound –Protocol TCP –LocalPort 1433 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like “SQL Admin Connection”)) {
            New-NetFirewallRule -DisplayName “SQL Admin Connection” -Direction Inbound –Protocol TCP –LocalPort 1434 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like “SQL Database Management”)) {
            New-NetFirewallRule -DisplayName “SQL Database Management” -Direction Inbound –Protocol UDP –LocalPort 1434 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like “SQL Service Broker”)) {
            New-NetFirewallRule -DisplayName “SQL Service Broker” -Direction Inbound –Protocol TCP –LocalPort 4022 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like “SQL Debugger/RPC”)) {
            New-NetFirewallRule -DisplayName “SQL Debugger/RPC” -Direction Inbound –Protocol TCP –LocalPort 135 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like “SQL Browser”)) {
            New-NetFirewallRule -DisplayName “SQL Browser” -Direction Inbound –Protocol TCP –LocalPort 2382 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like “SQL Server Browse Button Service”)) {
            New-NetFirewallRule -DisplayName “SQL Server Browse Button Service” -Direction Inbound –Protocol UDP –LocalPort 1433 -Action allow
        }
    }

    #Install SSMS
    Install-BTRSofware -Name "SQL Server Management Studio" -Instance $BeaterInstance -VMName DB1 -Installer "SSMS-Setup-ENU.exe" -WebLink 'https://aka.ms/ssmsfullsetup' -Args "/install /quiet /passive /norestart"
}
#endregion



#Install-BTREnvironment -Instance $BeaterInstance
#Install-BRTADK -BaseImage $2019BaseImage

#Create-BaseVM -BaseImage $2019BaseImage
#Create-BTRISO -BaseImage $2019BaseImage
#Configure-BTRBaseImage -BaseImage $2019BaseImage
#Prep-BTRBaseImage -BaseImage $2019BaseImage

#Install-BTRDomain -Instance $BeaterInstance
#Configure-BTRDomain -Instance $BeaterInstance
#SetUp-BTRDHCPServer -Instance $BeaterInstance

$ComputerName = 'Test1'
New-BTRVMFromTemplate -Instance $BeaterInstance -VMName $ComputerName -BaseImage $2019BaseImage
$IP = Get-NextIP -Instance $BeaterInstance
Add-BtrDNSRecord -Instance $BeaterInstance  -RecordName $ComputerName -IPAddress $IP
Apply-BTRVMCustomConfig -VMName $ComputerName -Instance $BeaterInstance -IpAddress $IP -JoinDomain $True -BaseImage $2019BaseImage
Start-VM -Name $ComputerName
"Start Wait at $(Get-Date)"
Wait-BTRVMOnline -VMName $ComputerName -Instance $BeaterInstance
"Stop Wait at $(Get-Date)"
Tweak-BTRVMPostDeloy -Instance $BeaterInstance -VMName $ComputerName
[System.Windows.MessageBox]::Show('Done')

#Install-BTRSQL -Instance $BeaterInstance -VMName DB1 -SQLISO "C:\Users\dkbluem1\Downloads\SW_DVD9_NTRL_SQL_Svr_Standard_Edtn_2019Nov2019_64Bit_English_OEM_VL_X22-18928.ISO"