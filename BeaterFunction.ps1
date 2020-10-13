
Function Write-BTRLog {
    Param (
        [Parameter(Mandatory = $True,ValueFromPipeline = $true)][String]$Entry,
        [ValidateSet('Error','Progress','Debug')][String]$Level = "Progress"
    )

    #Write to Log
    If ($LogLevel -eq "Debug") {
        $Entry >> $LogFile
    }ElseIf ($LogLevel -eq "Progress" -and $Level -eq "Progress") {
        $Entry >> $LogFile
    }ElseIf ($Level -eq "Error") {
        $Entry >> $LogFile
    }

    #Write to console
    If ($ConsoleLevel -eq "Debug") {
        Write-Host $Entry
    }ElseIf ($ConsoleLevel -eq "Progress" -and $Level -eq "Progress") {
        Write-Host $Entry
    }ElseIf ($Level -eq "Error") {
        Read-Host $Entry
    }
}

Function Read-BTRFromRegistry {
    Param (
        [Parameter(Mandatory=$True)][String]$Root
    )

    #Test if root exists
    If (!(Test-Path $Root -ErrorAction SilentlyContinue)) {
        Write-BTRLog "$Root does not exist." -Level Error
        Return $false
    }

    $TempHash = @{}
    
    $Error.Clear()
    $Key = [Microsoft.Win32.RegistryKey]::OpenBaseKey('localmachine','Registry64').OpenSubkey($Root.Replace("HKLM:",""))
    If ($Error) {
        Write-BTRLog -Level Error -Entry "Unable to open registry for reading"
        Return $False
    }

    ForEach ($Name In $Key.GetValueNames()) {
        If ($Key.GetValueKind($Name) -eq 'String') {
            $TempHash.add($Name, $Key.GetValue($Name))
        }
    }

    ForEach ($SubKeyName In $Key.GetSubKeyNames()) {
        $TempHash.Add($SubKeyName, (Read-BTRFromRegistry -Root "$Root\$SubKeyName"))
    }

    Return $TempHash

}

Function Write-BTRToRegistry {
    Param (
        [Parameter(Mandatory=$True)][HashTable]$Item,
        [Parameter(Mandatory=$True)][String]$Root
    )

    #Test if root exists
    If (!(Test-Path $Root -ErrorAction SilentlyContinue)) {
        Write-BTRLog "$Root does not exist." -Level Error
        Return $false
    }

    ForEach ($SubItem In $Item.GetEnumerator()) {
        If ($SubItem.Value.GetType().Name -eq 'String') {
            #Add new propperty
            #"Adding to $Root $($Item.Key) $($Item.Value)"
            If (!((Get-ItemProperty -Path "$Root" -ErrorAction SilentlyContinue | Select -ExpandProperty $SubItem.Key -ErrorAction SilentlyContinue) -eq $SubItem.Value)) {
                $Error.Clear()
                New-ItemProperty -Path "$Root" -Name $SubItem.Key -Value $SubItem.Value -PropertyType "String" -Force -Confirm:$false -ErrorAction SilentlyContinue *>&1 | Out-Null
                If ($Error) {
                    Write-BTRLog "Can't add string value $Name to $Root. Error: $($Error[0].Exception.Message)." -Level Error
                    Return $false
                }
            }
        }ElseIf($SubItem.Value.GetType().Name -eq 'Hashtable') {
            $NewRoot = "$Root\$($SubItem.Key)"
            #Create Key
            If (!(Test-Path "$NewRoot" -ErrorAction SilentlyContinue)) {
                $Error.Clear()
                New-Item -Path $Root -Name $SubItem.Key -Force -Confirm:$false -ErrorAction SilentlyContinue *>&1 | Out-Null
                If ($Error) {
                    Write-BTRLog "Can't create $NewRoot. Error: $($Error[0].Exception.Message)." -Level Error
                    Return $false
                }
            }
            #Call Self for Hashtable
            Write-BTRToRegistry -Item $SubItem.Value -Root $NewRoot
        }
            
    }
}

Function Validate-BTRHostconfig {
    Param (
        [Parameter(Mandatory=$True)]$Config
    ) 

    If (!($Config.RootPath)) {
        Write-BTRLog -Level Debug -Entry "Root Path not defined"
        Return $False
    }

    Return $True
}

Function Validate-BTRInstanceconfig {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    ) 

    $ManditoryProperties = @(
        "Host",
        "Name",
        "DomainName",
        "NBDomainName",
        "IPPrefix",
        "Gateway",
        "SubnetMask",
        "SubnetLength",
        "UseDHCP",
        "DHCPStart",
        "DHCPStop",
        "AdminName",
        "AdminNBName",
        "AdminPassword",
        "DomainController",
        "DomainControllerIP",
        "HDDPath",
        "VMPath",
        "SnapshotPath",
        "WorkingFolder",
        "CertFolder",
        "AppFolder",
        "VMTempFolder",
        "SwitchName",
        "UseNAT",
        "TimeZone"
    )

    ForEach ($ManditoryProperty In $ManditoryProperties) {
        If (!($Instance[$ManditoryProperty])) {
            Write-BTRLog "$ManditoryProperty is not set" -Level Error
            Return $False
        }
    }

    Return $True
}

Function Validate-BTRHost {
    Param (
        [Parameter(Mandatory=$True)][HashTable]$Config
    )

    #Make sure root path exists
    If (!(Test-Path $Config.RootPath -ErrorAction SilentlyContinue)) {
        Write-BTRLog -Level Debug -Entry "Root Path $($Config.RootPath) does not exits"
        Return $False
    }

    #Make sure Hyper-V is installed
    If (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V* -ErrorAction SilentlyContinue | Where State -NE 'Enabled') {
        Write-BTRLog "Hyper-V is not installed, or not all features are installed." -Level Debug
        Return $False
    }

    #Make sure ADK is installed
    If ($Config.OscdimgPath) {
        If (!(Test-Path $Config.OscdimgPath)) {
           Write-BTRLog "ADK is not installed" -Level Debug
           Return $False
        }
    }Else{
        Write-BTRLog "Path to Oscdimg.exe is not defined" -Level Debug
        Return $False
    }

    Return $True
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
    }Until (Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {$Temp = Get-ChildItem C:\ } -ErrorAction SilentlyContinue )
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
                    Invoke-WebRequest -Uri $WebLink -OutFile $Using:VMFullPath -ErrorAction SilentlyContinue
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


Function Configure-BTRServer {
     Param (
        [Parameter(Mandatory=$True)]$Config
    )
    #Install Hyper-V if it's not enabled
    Write-BTRLog "Checking if Hyper-V is installed" -Level Debug
    If (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V* -ErrorAction SilentlyContinue | Where State -NE 'Enabled') {
        Write-BTRLog "Hyper-V is not installed.  Attempting to Install." -Level Progress
        $Error.Clear()
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -ErrorAction:SilentlyContinue
        If ($Error) {
            Write-BTRLog "Failed to installed Hyper-V. Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }Else {
            Write-BTRLog "Installed Hyper-V.  You must now reboot and run this script again to continue" -Level Progress
            Return $False
        }
    }Else{
        Write-BTRLog "Hyper-V is already installed" -Level Progress
    }

    #Make sure ADK is installed
    If ($Config.OscdimgPath) {
        Write-BTRLog -Entry "OscdimgPath is defined.  Making sure it exists" -Level Debug
        If (Test-Path "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" -ErrorAction SilentlyContinue) {
            Write-BTRLog -Entry "oscdimg.exe located." -Level Debug
            $ADKInstalled = $True
        }Else{
            Write-BTRLog -Entry "OscdimgPath is set, but ADK does not appear to be installed there.  ADK will need to be installed." -Level Debug
            $ADKInstalled = $False
        }
    }Else{
        Write-BTRLog -Entry "OscdimgPath is not defined, checking for default ADK install." -Level Debug
        If (Test-Path "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" -ErrorAction SilentlyContinue) {
            Write-BTRLog -Entry "oscdimg.exe found at default location, setting path." -Level Debug
            $Config.Add('OscdimgPath','C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe')
            $ADKInstalled = $True
        }Else{
            Write-BTRLog -Entry "oscdimg.exe not found.  ADK will need to be installed." -Level Debug
            $ADKInstalled = $False
        }
    }
             
    If (!($ADKInstalled)) {
        Write-BTRLog "Determining the right version of ADK to download" -Level Debug
        $InstallFile = "$($env:TEMP)\adksetup.exe"
        $WinVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId
        If ($Winver -eq 1903) {
            $URL = "https://go.microsoft.com/fwlink/?linkid=2086042"
        } ElseIf ($WinVer -eq 1809) {
            $URL = " https://go.microsoft.com/fwlink/?linkid=2026036"
        } ElseIf ($Winver -eq 1803) {
            $URL = " https://go.microsoft.com/fwlink/?linkid=873065"
        } ElseIf ($Winver -eq 1709) {
            $URL = " https://go.microsoft.com/fwlink/p/?linkid=859206"
        } Else{
            Write-BTRLog "Unknown Windows Version $WinVer." -Level Error
        }
        Write-BTRLog "Getting ADK installer For Windows 10 $WinVer" -Level Debug
        $Error.Clear()
        Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/?linkid=2086042 -OutFile $InstallFile -ErrorAction SilentlyContinue
        If ($Error) {
            Write-BTRLog "Failed to download ADK installer. Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }

        If (Test-Path $InstallFile) {
            Write-BTRLog "Installing ADK from $InstallFile" -Level Progress
            $Error.Clear()
            Start-Process "$InstallFile" -ArgumentList "/quiet /features OptionId.DeploymentTools" -Wait -NoNewWindow -ErrorAction SilentlyContinue
            If ($Error){
                Write-BTRLog "Failed to install ADK. Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                 Write-BTRLog "Installed ADK." -Level Progress
                 If (Test-Path "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" -ErrorAction SilentlyContinue) {
                    Write-BTRLog -Entry "oscdimg.exe found at default location, setting path." -Level Debug
                    $Config.Add('OscdimgPath','C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe')
                }Else{
                    Write-BTRLog "ADK setup finished, but oscdimg.exe was not found.  Good luck you're on your own!" -Level Error
                    Return $False
                }
            }
            Write-BTRLog "Cleaning up $InstallFile." -Level Debug
            Remove-Item $InstallFile -Force -Confirm:$False -ErrorAction SilentlyContinue
            $Error.Clear()

        }Else{
            Write-BTRLog  "Unable to download ADK.  Good luck, you're on your own." -Level Error
            Return $False
        }
    }

    #Verify Root Folder exists
    If (!(Test-Path $($Config.RootPath))) {
        Write-BTRLog "$($Config.RootPath) does not exist. Creating" -Level Debug
        $Error.Clear()
        New-Item $Config.RootPath -ItemType "Directory" -Confirm:$False -Force | Out-Null
        If ($Error) {
            Write-BTRLog "Unable to create $($Config.RootPath). Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }
    }Else{
        Write-BTRLog "$($Config.RootPath) already exists" -Level Debug
    }

    Return $True
}


Function Configure-BTRInstance {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )
    Write-BTRLog "Entering Install-BTREnvironment" -Level Debug

    #Create folders if they don't exist
    If (!(Test-Path $($Instance.WorkingFolder))) {
        Write-BTRLog "$($Instance.WorkingFolder) does not exist. Creating" -Level Debug
        New-Item $($Instance.WorkingFolder) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $($Instance.VMPath))) {
        Write-BTRLog "$($Instance.VMPath) does not exist. Creating" -Level Debug
        New-Item $($Instance.VMPath) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $($Instance.HDDPath))) {
        Write-BTRLog "$($Instance.HDDPath) does not exist. Creating" -Level Debug
        New-Item $($Instance.HDDPath) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $Instance.SnapshotPath)) {
        Write-BTRLog "$($Instance.SnapshotPath) does not exist. Creating" -Level Debug
        New-Item $Instance.SnapshotPath -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }

    #Create Network Switch
    Write-BTRLog "Checking if vSwitch $($Instance.SwitchName) exists." -Level Debug
    If (!(Hyper-V\Get-VMSwitch -ErrorAction SilentlyContinue | Where Name -eq $Instance.SwitchName)) {
        Write-BTRLog "$($Instance.SwitchName) does not exist." -Level Debug
        If ($Instance.UseNAT) {
            Write-BTRLog "Instance $($Instance.Name) is set to use NAT. Creating $($Instance.SwitchName) as an Internal Switch." -Level Progress
            $Error.Clear()
            Hyper-V\New-VMSwitch -SwitchName $Instance.SwitchName -SwitchType Internal -ComputerName $Instance.Host
            If ($Error) {
                Write-BTRLog "Can't create new switch. Error: $($Error[0].Exception.Message)" -Level Error
                Return
            }Else{
                Write-BTRLog "Created vSwitch $($Instance.SwitchName) as Internal" -Level Debug
            }
        }Else{
            Write-BTRLog "Instance $($Instance.Name) is NOT set to use NAT. Creating $($Instance.SwitchName) as a Private Switch." -Level Progress
            $Error.Clear()
            Hyper-V\New-VMSwitch -SwitchName $Instance.SwitchName -SwitchType Private -ComputerName $Instance.Host
            If ($Error) {
                Write-BTRLog "Can't create new switch. Error: $($Error[0].Exception.Message)" -Level Error
                Return
            }Else{
                Write-BTRLog "Created vSwitch $($Instance.SwitchName) as Private" -Level Debug
            }
        }
    }Else{
        Write-BTRLog "vSwitch $($Instance.SwitchName) already exists" -Level Debug
    }
    
    #Setup NAT
    If ($Instance.UseNAT) {
        Write-BTRLog "Instance $($Instance.Name) is set to use NAT." -Level Debug
        Write-BTRLog "Checking if host has NIC with IP $($Instance.Gateway)" -Level Debug
        If (!(Get-NetAdapter | Where name -Like "*$($Instance.SwitchName)*" -ErrorAction SilentlyContinue | Get-NetIPAddress -ErrorAction SilentlyContinue | Where IPAddress -like $Instance.Gateway)) {
            Write-BTRLog "Looking for host NIC attached to $($Instance.SwitchName)" -Level Debug
            If (!($Index = Get-NetAdapter | Where name -Like "*$($Instance.SwitchName)*" | Select -ExpandProperty ifIndex)) {
                Write-BTRLog "Can't find instance switch. Error: $($Error[0].Exception.Message)" -Level Error
                Return
            }Else{
                Write-BTRLog "Host NIC attached to $($Instance.SwitchName) is Index $Index." -Level Debug
            }
            $Error.Clear
            Write-BTRLog "Assigning $($Instance.Gateway) to host NIC with Index $Index." -Level Progress
            New-NetIPAddress -IPAddress $Instance.Gateway -PrefixLength $Instance.SubnetLength -InterfaceIndex $Index
            Write-BTRLog "Verifying $($Instance.Gateway) is assigned to host NIC with Index $Index." -Level Degug
            $Error.Clear()
            If ((!(Get-NetAdapter -ErrorAction SilentlyContinue | Where name -Like "*$($Instance.SwitchName)*" | Select -ExpandProperty ifIndex))) {
                Write-BTRLog "Can't set IP on instance switch. Error: $($Error[0].Exception.Message)" -Level Error
            }Else{
                Write-BTRLog "Verified Host NIC with Index $Index is assinged IP $($Instance.Gateway)" -Level Debug
            }
        }Else{
            Write-BTRLog "Host already has IP set for NIC attached to vSwitch $($Instance.SwitchName)." -Level Debug
        }

        #Setting network to private
        Write-BTRLog "Checking if network is set to Private" -Level Debug
        If ($(Get-NetConnectionProfile | Where InterfaceAlias -Like "*Beater*" | select -ExpandProperty NetworkCategory) -ne 'Private' ) {
            Write-BTRLog "Setting network to Private" -Level Progress
            Get-NetConnectionProfile | Where InterfaceAlias -Like "*$($Instance.SwitchName)*" | Set-NetConnectionProfile -NetworkCategory Private
        }Else{
            Write-BTRLog "Network is already set to progress" -Level Debug
        }

        #Create NAT
        Write-BTRLog "Checking if a NAT exists for $($Instance.Name)" -Level Debug
        If (!(Get-NetNat | Where InternalIPInterfaceAddressPrefix -eq "$($Instance.IPPrefix).0/$($Instance.SubnetLength)")) {
            Write-BTRLog "NAT does not exist for $($Instance.Name). Creating" -Level Debug
            $Error.Clear()
            New-NetNat -Name "$($Instance.SwitchName)NAT" -InternalIPInterfaceAddressPrefix "$($Instance.IPPrefix).0/$($Instance.SubnetLength)"
            If ($Error) {
                Write-BTRLog "Can't create NAT. Error: $($Error[0].Exception.Message)" -Level Error
            }
        }Else{
            Write-BTRLog "NAT already exists." -Level Debug
        }

    }Else{
        Write-BTRLog "Instance $($Instance.Name) is not set to use NAT.  Skipping host IP check." -Level Debug
    }
    Write-BTRLog "Exiting Install-BTREnvironment" -Level Debug
}

Function Delete-BTRInstance {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Switch]$DeleteVMs,
        [Switch]$DeleteFolders
    )

}


Function Create-BTRISO {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)]$BaseImage
    )    
    Write-BTRLog "Entering Create-BTRISO"

   Write-BTRLog "Making sure $($BaseImage.InstallMedia) exits"
   If (!(Test-Path $BaseImage.InstallMedia)) {
       Write-BTRLog "$($BaseImage.InstallMedia) dosn't exist" -Level Error
       Return
   }Else{
       Write-BTRLog "$($BaseImage.InstallMedia) found" -Level Debug
   }

   Write-BTRLog "Making sure $($Instance.OscdimgPath) exits"
   If (!(Test-Path $BaseImage.InstallMedia)) {
       Write-BTRLog "$($Instance.OscdimgPath) dosn't exist" -Level Error
       Return
   }Else{
       Write-BTRLog "$($Instance.OscdimgPath) found" -Level Debug
   }

   
   Write-BTRLog "Making sure $($Instance.WorkingFolder) exists" -Level Debug
   $Error.Clear()
   If (!(Test-Path $Instance.WorkingFolder -ErrorAction SilentlyContinue) -or $Error) {
       Write-BTRLog "$($Instance.WorkingFolder) dosn't exist" -Level Error
       Return
   }Else{
       Write-BTRLog "$($Instance.WorkingFolder) found" -Level Debug
   }
   
   $ExtractFolder = "$($Instance.WorkingFolder)\ISO"
   
   Write-BTRLog "Seeing if Extract Folder $ExtractFolder exists." -Level Debug
   If (Test-Path $ExtractFolder) {
       Write-BTRLog "Extract Folder $ExtractFolder found.  Cleaning up." -Level Debug
       $Error.Clear()
       Remove-Item -Path "$ExtractFolder\*" -Force -Confirm:$False -Recurse -ErrorAction SilentlyContinue  *>&1 | Out-Null
       If ($Error) {
           Write-BTRLog "Unable to clean up $ExtractFolder. Error: $($Error[0].Exception.Message)" -Level Error
           Return
       }Else{
           Write-BTRLog "Cleaned up $ExtractFolder." -Level Progress
       }
   }Else{
       Write-BTRLog "Extract Folder $ExtractFolder not found.  Creating." -Level Debug
       $Error.Clear()
       New-Item -Path $ExtractFolder -ItemType Directory -Force -Confirm:$False -ErrorAction SilentlyContinue  *>&1 | Out-Null
       If ($Error) {
           Write-BTRLog "Unable to create $ExtractFolder. Error: $($Error[0].Exception.Message)" -Level Error
           Return
       }Else{
           Write-BTRLog "Created $ExtractFolder." -Level Progress
       }
   } 
   
   Write-BTRLog "Mounting $($BaseImage.InstallMedia)" -Level Debug
   $Error.Clear()
   Mount-DiskImage -ImagePath $BaseImage.InstallMedia -ErrorAction SilentlyContinue *>&1 | Out-Null
   $DriveLetter = (Get-DiskImage -ImagePath $BaseImage.InstallMedia -ErrorAction SilentlyContinue | Get-Volume).DriveLetter
   If ($Error) {
       Write-BTRLog "Unable to mount $($BaseImage.InstallMedia). Error: $($Error[0].Exception.Message)" -Level Error
       Return
   }Else{
       Write-BTRLog "Mounted $($BaseImage.InstallMedia) on $DriveLetter`:." -Level Progress
   }
   
   Write-BTRLog "Copying files from $($BaseImage.InstallMedia) to $ExtractFolder" -Level Debug
   $Error.Clear()
   Copy-Item -Path "$DriveLetter`:\*" -Destination $ExtractFolder -Force -Recurse -Confirm:$False
   If ($Error) {
       Write-BTRLog "Unable to copy files from $($BaseImage.InstallMedia) to $ExtractFolder. Error: $($Error[0].Exception.Message)" -Level Error
       Return
   }Else{
       Write-BTRLog "Copied files from $($BaseImage.InstallMedia) to $ExtractFolder." -Level Progress
   }
   
   Write-BTRLog "Dismounting $($BaseImage.InstallMedia)" -Level Debug
   $Error.Clear()
   Dismount-DiskImage -ImagePath $BaseImage.InstallMedia -ErrorAction SilentlyContinue  *>&1 | Out-Null
   If ($Error) {
       Write-BTRLog "Failed to dismount $($BaseImage.InstallMedia). Error: $($Error[0].Exception.Message)" -Level Error
       Return
   }Else{
       Write-BTRLog "Dismounted $($BaseImage.InstallMedia)." -Level Progress
   }
   
   Write-BTRLog 'Modifying files to disable "Hit Any Key to Boot from CD" message' -Level Debug
   $Error.Clear()
   Rename-Item -Path "$ExtractFolder\efi\microsoft\boot\cdboot.efi" -NewName cdboot-prompt.efi -Force -Confirm:$False -ErrorAction SilentlyContinue
   Rename-Item -Path "$ExtractFolder\efi\microsoft\boot\cdboot_noprompt.efi" -NewName cdboot.efi -Force -Confirm:$False -ErrorAction SilentlyContinue
   Rename-Item -Path "$ExtractFolder\efi\microsoft\boot\efisys.bin" -NewName efisys_prompt.bin -Force -Confirm:$False -ErrorAction SilentlyContinue
   Rename-Item -Path "$ExtractFolder\efi\microsoft\boot\efisys_noprompt.bin" -NewName efisys.bin -Force -Confirm:$False -ErrorAction SilentlyContinue
   Remove-Item -Path "$ExtractFolder\boot\bootfix.bin" -Force -Confirm:$False -ErrorAction SilentlyContinue
   If ($Error) {
       Write-BTRLog "Failed to modiy boot files. Error: $($Error[0].Exception.Message)" -Level Error
       Return
   }Else{
       Write-BTRLog "Modified boot files." -Level Progress
   }
   
   #region autounattend.xml
    Write-BTRLog "Creating autounattend.xml" -Level Debug
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
                                <Value>' + $BaseImage.ImageIndex + '</Value>
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
                <AutoLogon>
                   <Password>
                      <Value>' + $Instance.AdminPassword + '</Value> 
                      <PlainText>true</PlainText> 
                   </Password>
                   <Username>Administrator</Username> 
                   <Enabled>true</Enabled> 
                   <LogonCount>1</LogonCount> 
                </AutoLogon>
                <UserAccounts>
                    <LocalAccounts>
                        <LocalAccount wcm:action="add">
                            <Password>
                                <Value>' + $Instance.AdminPassword + '</Value>
                                <PlainText>true</PlainText>
                            </Password>
                            <Description>EnableAdmin</Description>
                            <DisplayName>Administrator</DisplayName>
                            <Group>Administrators</Group>
                            <Name>Administrator</Name>
                        </LocalAccount>
                    </LocalAccounts>
                </UserAccounts>
            </component>
        </settings>
    </unattend>'
    #endregion
   
   $UnattendContent > "$ExtractFolder\autounattend.xml"
   Write-BTRLog "Done creating autounattend.xml"
   
   Write-BTRLog "Checking for existing $($BaseImage.CustomISO)." -Level Debug
   If (Test-Path $BaseImage.CustomISO -ErrorAction SilentlyContinue) {
       Write-BTRLog "Old $($BaseImage.CustomISO) found. Deleteing" -Level Debug
       $Error.Clear()
       Remove-Item $BaseImage.CustomISO -Force -Confirm:$False -ErrorAction SilentlyContinue
       If ($Error) {
           Write-BTRLog "Failed to delete $($BaseImage.CustomISO). Error: $($Error[0].Exception.Message)" -Level Error
           Return
       }Else{
           Write-BTRLog "Deleted $($BaseImage.CustomISO)" -Level Progress
       }
   }

    Write-BTRLog "Writing out $($BaseImage.CustomISO).  This will take a while!" -Level Progress
    Write-BTRLog "Running from $($Instance.OscdimgPath)." -level Debug
    $Args = "-m -o -u2 -udfver102 -bootdata:2#p0,e,b`"$ExtractFolder\boot\etfsboot.com`"#pEF,e,b`"$ExtractFolder\efi\microsoft\boot\efisys.bin`" `"$ExtractFolder`" $($BaseImage.CustomISO)"
        Write-BTRLog "With Arguments $Args" -level Debug
    $Error.Clear()
    Start-Process -FilePath $Instance.OscdimgPath -ArgumentList $Args  -Wait -WindowStyle Normal -ErrorAction SilentlyContinue
    If ($LASTEXITCODE -or $Error) {
        Write-BTRLog "Failed to create $($BaseImage.CustomISO).  Error Code $LASTEXITCODE." -Level Error
        Return
    }Else{
        Write-BTRLog "Created $($BaseImage.CustomISO)" -Level Progress
    }

    Write-BTRLog "Deleting $ExtractFolder" -Level Debug
    $Error.Clear()
    Remove-Item -Path "$ExtractFolder" -Force -Confirm:$False -Recurse -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to delete $ExtractFolder. Error: $($Error[0].Exception.Message)" -Level Error
    }Else{
        Write-BTRLog "Deleted $ExtractFolder." -Level Progress
    }

    Write-BTRLog "Exiting Create-BTRISO." -Level Debug
}

Function Create-BTRBaseVM {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)]$BaseImage
    )

    Write-BTRLog "Entering Create-BtrBaseVM" -Level Debug

    $VMName = $BaseImage.Name
    Write-BTRLog "VMName will be $VMName" -Level Debug
    
    Write-BTRLog "Checking if $VMName exists" -Level Debug
    If (Hyper-V\Get-VM -ErrorAction SilentlyContinue | Where Name -EQ $VMName) {
        Write-BTRLog "$VMName already exists" -Level Error
        Return
    }Else{
        Write-BTRLog "$VMName does not exist" -Level Debug
    }

    Write-BTRLog "Creating $VMName" -Level Debug
    $Error.Clear()
    $VM = Hyper-V\New-VM -Name $VMName -MemoryStartupBytes 1024MB -Generation 2 -Path $Instance.VMPath -ErrorAction SilentlyContinue 
    If ($Error) {
        Write-BTRLog "Unable to Create $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Created $VMName." -Level Progress
    }

    Write-BTRLog "Setting CPU count and checkpoints on $VMName" -Level Debug
    $Error.Clear()
    Hyper-V\Set-VM -Name $VMName -ProcessorCount 3 -AutomaticCheckpointsEnabled:$False -Confirm:$False -CheckpointType Production -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to configure $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Configured $VMName." -Level Debug
    }

    Write-BTRLog "Connecting $VMName to vSwitch $($Instance.SwitchName)" -Level Debug
    $Error.Clear()
    Hyper-V\Connect-VMNetworkAdapter -VMName $VMName -SwitchName $Instance.SwitchName -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to connect $VMName to vSwitch $($Instance.SwitchName). Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Connected $VMName to vSwitch $($Instance.SwitchName)" -Level Debug
    }

    Write-BTRLog "Configuring Integration Services on $VMName" -Level Debug
    $Error.Clear()
    Hyper-V\Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to configure Integration Services on $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Configured Integration Services on $VMName" -Level Debug
    }

    Write-BTRLog "Creating HDD $($BaseImage.BaseImage)." -Level Debug
    $Error.Clear()
    Hyper-V\New-VHD -Path $BaseImage.BaseImage -Dynamic -SizeBytes 40GB -ErrorAction SilentlyContinue *>&1 | Out-Null
    If ($Error) {
        Write-BTRLog "Unable to create HDD $($BaseImage.BaseImage). Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Created HDD $($BaseImage.BaseImage)." -Level Debug
    }

    Write-BTRLog "Attaching HDD $($BaseImage.BaseImage) to $VMName" -Level Debug
    $Error.Clear()
    Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $BaseImage.BaseImage -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to attach HDD $($BaseImage.BaseImage) to $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Attached HDD $($BaseImage.BaseImage) to $VMName." -Level Debug
    }

    Write-BTRLog "Attaching DVD $($BaseImage.CustomISO) to $VMName" -Level Debug
    $Error.Clear()
    Hyper-V\Add-VMDvdDrive -VMName $VMName -Path $BaseImage.CustomISO -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to attach DVD $($BaseImage.CustomISO) to $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Attached DVD $($BaseImage.CustomISO) to $VMName." -Level Debug
    }

    Write-BTRLog "Setting boot order." -Level Debug
    $Error.Clear()
    $DVDDrive = Hyper-V\Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue
    $BootHDD = Hyper-V\Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue
    Hyper-V\Set-VMFirmware -VMName $VMName -EnableSecureBoot Off -BootOrder $DVDDrive, $BootHDD -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to attach DVD $($BaseImage.CustomISO) to $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Attached DVD $($BaseImage.CustomISO) to $VMName." -Level Debug
    }
}

Function Configure-BTRBaseImage {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)]$BaseImage
    )

    Write-BTRLog "Entering configure-BTRBaseImage" -Level Debug

    $VMName = $BaseImage.Name
    Write-BTRLog "Making sure $VMName exists" -Level Debug
    If (!(Hyper-V\Get-VM | Where Name -EQ $VMName)) {
        Write-BTRLog "$VMName does not exist" -Level Error
        Return
    }

    Write-BTRLog "Checking if base image is set to use static IP" -Level Debug
    If (!($BaseImage.UseDHCP)) {
        Write-BTRLog "Base image is set to use static IP" -Level Debug
        Write-BTRLog "Checking if instance domain controller IP $($Instance.DomainControllerIP) is available" -Level Debug
        If (!(Test-Connection -ComputerName $Instance.DomainControllerIP -Quiet -Count 1 -ErrorAction SilentlyContinue)) {
            Write-BTRLog "$($Instance.DomainControllerIP) is free.  Using that" -Level Debug
            $IP = $Instance.DomainControllerIP
        }Else{
            Write-BTRLog "Instance Domain Controller is online.  Checking for next free address" -Level Debug
            $Error.Clear()
            $IP = Get-NextIP -Instance $Instance
            If ($Error) {
                Write-BTRLog "Couldn't get next IP from DC.  Defaulting to $($Instance.IPPrefix).253" -Level Debug
                $IP = "$($Instance.IPPrefix).253"
            }Else{
                Write-BTRLog "Next free IP is $IP"
            }
        }

        Write-BTRLog "Getting host DNS servers" -Level Debug
        $Error.Clear()
        $DNSServers = Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Where AddressFamily -eq 2 | Where ServerAddresses | Select -ExpandProperty ServerAddresses
        If ($Error) {
            Write-BTRLog "Unable to retreive host DNS servers. Error: $($Error[0].Exception.Message)" -Level Error
            Return
        }Else{
            If (!($DNSServers)) {
                Write-BTRLog "Unable to retreive host DNS servers" -Level Error
                Return
            }Else{
                Write-BTRLog "Host is using DNS Servers" -Level Debug
                ForEach ($DNSServer In $DNSServers) {
                    Write-BTRLog "   $DNSServer" -Level Debug
                }
            }
        }

        Write-BTRLog "Getting VM Mac Address." -Level Debug
        $MacAddress = $(Hyper-V\Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select -ExpandProperty MACAddress) -replace "([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])", '$1$2-$3$4-$5$6-$7$8-$9$10-$11$12'
        If ($MacAddress.Length -ne 17) {
            Write-BTRLog "Unable to get Mac address" -Level Error
            Return
        }Else{
            Write-BTRLog "VM $VMName has MAC address $MacAddress" -Level Debug
        }

        Write-BtrLog "Setting IP to $IP" -Level Debug
        $Error.Clear()
        Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock { 
            $IfIndex = Get-NetAdapter -ErrorAction SilentlyContinue | WHERE MacAddress -eq $Using:MacAddress | Select -ExpandProperty ifIndex
            New-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -IPAddress $Using:IP -PrefixLength $Using:Instance.SubnetLength -DefaultGateway $Using:Instance.Gateway
        }
        If($Error) {
            Write-BTRLog "Failed to set static IP to $IP. Error: $($Error[0].Exception.Message)" -Level Error
            Return
        }Else{
            Write-BTRLog "Set static IP to $IP." -Level Debug
        }

        Write-BtrLog "configuring DNS" -Level Debug
        $Error.Clear()
        Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
            $IfIndex = Get-NetAdapter -ErrorAction SilentlyContinue | WHERE MacAddress -eq $Using:MacAddress | Select -ExpandProperty ifIndex
            Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $Using:DNSServers
            Set-DnsClient -InterfaceIndex $IfIndex -RegisterThisConnectionsAddress $False
        }
        If($Error) {
            Write-BTRLog "Failed to configure DNS. Error: $($Error[0].Exception.Message)" -Level Error
            Return
        }Else{
            Write-BTRLog "Configured DNS" -Level Debug
        }
    }Else{
        Write-BTRLog "Base Image is set to use DHCP." -Level Debug
    }

    Write-BtrLog "Disabling IPv6" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock { 
        Get-NetAdapter -ErrorAction SilentlyContinue | foreach { Disable-NetAdapterBinding -InterfaceAlias $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue }
    }
    If($Error) {
        Write-BTRLog "Failed to disable IPv6. Error: $($Error[0].Exception.Message)" -Level Debug
    }Else{
        Write-BTRLog "Disabled IPv6" -Level Debug
    }

    Write-BTRLog "Disabling IE Enhanced Security" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
        $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
        Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue
    }
    If($Error) {
        Write-BTRLog "Failed to disable IE Enhanced Security. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "Disabled IE Enhanced Security" -Level Progress
    }

    Write-BTRLog "Enabling RDP"
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0 *>&1 | Out-Null
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
        (Get-WmiObject -class Win32_TSGeneralSetting -Namespace root\cimv2\terminalservices -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(1) *>&1 | Out-Null
    }
    If($Error) {
        Write-BTRLog "Failed to enable RDP. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "Enabled RDP" -Level Progress
    }

    Write-BTRLog "Setting Time Zone" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        Set-TimeZone -Id $Using:Instance.TimeZone
    }
    If($Error) {
        Write-BTRLog "Failed to set Time Zone. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "Set Time Zone" -Level Progress
    }

    Write-BTRLog "Installing Optional Components" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        If ($(Get-WmiObject Win32_OperatingSystem).ProductType -ne 1) {
            Install-WindowsFeature -IncludeAllSubFeature RSAT -ErrorAction SilentlyContinue *>&1 | Out-Null
            Install-WindowsFeature -IncludeAllSubFeature GPMC -ErrorAction SilentlyContinue *>&1 | Out-Null
        }
        Add-WindowsCapability -Online -Name NetFx3~~~~ -Source D:\Sources\sxs -ErrorAction SilentlyContinue *>&1 | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName TFTP -NoRestart -ErrorAction SilentlyContinue *>&1 | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName TelnetClient -NoRestart -ErrorAction SilentlyContinue *>&1 | Out-Null
    }
    If($Error) {
        Write-BTRLog "Failed to install Optional Components. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "Installed Optional Components." -Level Progress
    }
    
    Write-BTRLog "Creating $($Instance.VMTempFolder)" -Level Debug
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        If (!(Test-Path $Using:Instance.VMTempFolder)) {
            New-Item $Using:Instance.VMTempFolder -ItemType Directory -Force -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
        }
    }

    Write-BTRLog "Installing Certficates" -Level Debug
    $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate
    If (!($Certificates = Get-ChildItem $Instance.CertFolder -ErrorAction SilentlyContinue)) {
        Write-BTRLog "Can't get list of certificates to install." -Level Debug
    }Else{
        ForEach ($Certificate In $Certificates) {
            $DestinationPath = "$($Instance.VMTempFolder)\$($Certificate.Name)"
            $Cert.Import($Certificate.FullName)
            Copy-VMFile $VMName -SourcePath $Certificate.FullName -DestinationPath $DestinationPath -CreateFullPath -FileSource Host -Force
            If ($Cert.Issuer -eq $Cert.GetName()) {
                Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
                    Import-Certificate -Filepath $Using:DestinationPath -CertStoreLocation "Cert:\LocalMachine\Root" *>&1 | Out-Null
                }
            }Else{
                Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
                    Import-Certificate -Filepath $Using:DestinationPath -CertStoreLocation "Cert:\LocalMachine\CA" *>&1 | Out-Null
                }
            }
        }
    }

    #Install Apps
    "Copying apps over"
    ForEach ($File In Get-ChildItem $Instance.AppFolder) {
        Hyper-V\Copy-VMFile -Name $VMName -SourcePath $File.FullName -DestinationPath "C:\Temp\$($File.Name)" -CreateFullPath -FileSource Host -Force #-Credential $Instance.LocalCreds
    }
    
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        "Installing Chrome"
        If (Test-Path "C:\Temp\GoogleChromeStandaloneEnterprise64.msi") {
            Start-Process Msiexec.exe -ArgumentList '/i "C:\Temp\GoogleChromeStandaloneEnterprise64.msi" /qb!' -Wait
            Unregister-ScheduledTask -TaskName "GoogleUpdateTaskMachineCore" -Confirm:$False *>&1 | Out-Null
            Unregister-ScheduledTask -TaskName "GoogleUpdateTaskMachineUA" -Confirm:$False *>&1 | Out-Null
            Get-Service "gupdate" | Stop-Service -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
            Get-Service "gupdate" | Set-Service -StartupType Disabled -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
            New-ItemProperty -Path "HKLM:\Software\Policies\Google\Chrome" -Name "HardwareAccelerationModeEnabled" -PropertyType "DWORD" -Value "1" -Force -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
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
        Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
            REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate /v TargetGroup /d SVDI /t REG_SZ /f *>&1 | Out-Null
            REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate /v TargetGroupEnabled /d 1 /t REG_DWORD /f *>&1 | Out-Null
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name WUServer -Value $Using:BaseImage.UpdateSource -Force -Confirm:$False *>&1 | Out-Null
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name WUStatusServer -Value $Using:BaseImage.UpdateSource -Force -Confirm:$False *>&1 | Out-Null
            REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU /v UseWUServer /d 1 /t REG_DWORD /f *>&1 | Out-Null
        }
    }

    "Installing Windows Update Module"
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        Set-ExecutionPolicy Unrestricted -Force -Confirm:$False *>&1 | Out-Null
        Install-PackageProvider -Name NuGet -ErrorAction SilentlyContinue *>&1 | Out-Null
        Register-PSRepository -Default -InstallationPolicy Trusted -ErrorAction SilentlyContinue *>&1 | Out-Null
        Install-Module -Name PSWindowsUpdate -ErrorAction SilentlyContinue *>&1 | Out-Null
        Import-Module -Name PSWindowsUpdate 
    }

    "Checking for updates"
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        Get-WindowsUpdate
    }

    "Installing updates"
    Invoke-Command -VMName $VMName -Credential $Instance.LocalCreds -ScriptBlock {
        Install-WindowsUpdate -AcceptAll -AutoReboot
    }

}

Function Prep-BTRBaseImage {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)]$BaseImage
    )

    #Make sure VM exists
    $VMName = $BaseImage.Name
    If (!(Hyper-V\Get-VM | Where Name -EQ $VMName)) {
        "$VMName does not exist"
        Return
    }

    #Figure out creditials
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminName,$SecurePassword)

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
        Install-WindowsFeature -Name AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools -Confirm:$False -ErrorAction SilentlyContinue
    }
    If ($IsBroken) {
        "Unable to install Domain role"
        Read-Host "Hit Enter to exit"
        Return
    }

    #Configure Domain
    $Error.Clear()
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        $SecurePassword = ConvertTo-SecureString -AsPlainText $Using:Instance.AdminPassword -Force
        Install-ADDSForest -DomainMode 7 -ForestMode 7 -InstallDNS -Force -DomainName $Using:Instance.DomainName -SafeModeAdministratorPassword $SecurePassword -DomainNetbiosName $Using:Instance.NBDomainName -ErrorAction SilentlyContinue
    }
    If ($Error) {
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

    Write-BTRLog "Powering ON $VMName. This is required to get a MAC address assigned." -Level Debug
    $Error.Clear()
    Hyper-V\Start-VM -Name $VMName -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to power on $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Powered on $VMName." -Level Debug
    }

    Write-BTRLog "Waiting 3 seconds." -Level Debug
    Start-Sleep -Seconds 3

    Write-BTRLog "Powering OFF $VMName." -Level Debug
    $Error.Clear()
    Hyper-V\Stop-VM -Name $VMName -TurnOff -Force -Confirm:$False -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to power off $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    } Else {
        Write-BTRLog "Powered off $VMName." -Level Debug
    }

    Write-BTRLog "Verifying that MAC address got assigned" -Level Debug
    $Mac = Hyper-V\Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select -ExpandProperty MACAddress
    If ($Error) {
        Write-BTRLog "Unable to find Mac Address for $VMName." -Level Error
        Return
    }ElseIf (!($Mac -match '^([0-9A-Fa-f]{12})$')) {
        Write-BTRLog "Unable to find Mac Address for $VMName." -Level Error
        Return
    Else
        Write-BTRLog "MAc address for $VMName is $Mac" -Level Debug
    }
}
    
Function Delete-BTRVM {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$VmName
    )

    Write-BTRLog "Entering Delete-BTRVM" -Level Debug

    #Connect Session to DC
    Write-BTRLog "Connecting to $($Instance.DomainController)."
    $Error.Clear()
    $DomainSession = New-PSSession -VMName $Instance.DomainController -Credential $Instance.DomainCreds
    If ($Error) {
        Write-BTRLog "Failed to create PS Session on $($Instance.DomainController). Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "Created PS Session to $($Instance.DomainController)" -Level Debug
    }

    If (!($VM = Hyper-V\Get-VM -Name $VmName -ErrorAction SilentlyContinue)) {
        Write-BTRLog "$VmName does not exist" -Level Error
        Return
    }

    #Turn Off VM
    Write-BTRLog "Checking if $VmName is powered off" -Level Debug
    If ($VM.State -ne 'Off') {
        Write-BTRLog "$VmName is powered on" -Level Debug
        Write-BTRLog "Powering off $VmName" -Level Progress
        $Error.Clear()
        Hyper-V\Stop-vm -Name $VmName -Force -TurnOff
        If ($Error) {
            Write-BTRLog "Unable to powering off $VmName. Error: $($Error[0].Exception.Message)" -Level Error
            Return
        }Else{
            Write-BTRLog "Powered off $VmName." -Level Debug
        }
    }Else{
        Write-BTRLog "$VmName is already off." -Level Debug
    }

    #Delete Snapshots
    Write-BTRLog "Removing all snapshots" -Level Debug
    $Error.Clear()
    $VM | Hyper-V\Remove-VMSnapshot -Name *
    If ($Error) {
        Write-BTRLog "Failed to remove snapshots. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "Removed snapshots" -Level Progress
    }

    #Get List of HDDs
    Write-BTRLog "Getting list of HDDs attached to $VmName." -Level Debug
    $Error.Clear()
    $HDDs = $VM | Select -ExpandProperty VMID | Get-VHD | Select -ExpandProperty Path
    If ($Error) {
        Write-BTRLog "Failed to retrive list of HDDs attached to $VmName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "HDDS attached to $VmName" -Level Debug
        ForEach ($HDD In $HDDs) {
            Write-BTRLog "     $HDD" -Level Debug
        }
    }
    $VMPath = $VM | Select -ExpandProperty Path
    Write-BTRLog "Vmpath is $VMPath." -Level Debug

    #DeleteVM
    Write-BTRLog "Deleting $VmName." -Level Debug
    $Error.Clear()
    $Vm | Hyper-V\Remove-VM -Force -Confirm:$False
    If ($Error) {
        Write-BTRLog "Failed to delete $VmName. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "Deleted $VmName" -Level Progress
    }

    #Delete HDDs
    Write-BTRLog "Deleting HDDs" -Level Progress
    ForEach ($HDD In $HDDs) {
        Write-BTRLog "Deleting $HDD" -Level Debug
        $Error.Clear()
        Remove-Item -Path $HDD -Force -Confirm:$False
        If ($Error) {
            Write-BTRLog "Failed to delete $HDD. Error: $($Error[0].Exception.Message)" -Level Error
            Return
        }Else{
            Write-BTRLog "Deleted $HDD" -Level Debug
        }
    }
    Write-BTRLog "Done Deleting Hard Drives" -Level Debug

    #Delete VM Folder
    Write-BTRLog "Deleting $VMPath" -Level Debug
    $Error.Clear()
    Remove-Item -Path $VMPath -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to delete $VMPath. Error: $($Error[0].Exception.Message)" -Level Error
        Return
    }Else{
        Write-BTRLog "Deleted $VMPath" -Level Progress
    }

    #Remove from DNS and AD
    Write-BTRLog "Checking if $VmName is in DNS" -Level Debug
    $DNs = Invoke-Command -Session $DomainSession -ScriptBlock {
        Try {
            Get-DnsServerResourceRecord -ZoneName $Using:Instance.DomainName -Name $Using:VMName -ErrorAction SilentlyContinue
        }Catch{
            #Do Nothing
        }
    }
    If ($DNS) {
        Write-BTRLog "DNS record for $VmName exists.  Deleting." -Level Debug
        Invoke-Command -Session $DomainSession -ScriptBlock {
            Get-DnsServerResourceRecord -ZoneName $Using:Instance.DomainName -Name $Using:VMName | Remove-DnsServerResourceRecord -ZoneName $Using:Instance.DomainName -Confirm:$False -Force
        }
        $Error.Clear()
        If ($Error) {
            Write-BTRLog "Failed to remove DNS records for $VmName. Error: $($Error[0].Exception.Message)" -Level Error
        }Else{
            Write-BTRLog "Remove DNS records for $VmName." -Level Debug
        }
    }Else{
        Write-BTRLog "DNS record for $VmName not found." -Level Debug
    }

    #Remove AD object
    Write-BTRLog "Checking if $VmName is in DNS" -Level Debug
    If (Invoke-Command -Session $DomainSession -ScriptBlock {Get-ADComputer $Using:VMName -ErrorAction SilentlyContinue }) {
        Write-BTRLog "Domputer account for $VmName exists.  Deleting." -Level Debug
        Invoke-Command -Session $DomainSession -ScriptBlock {
            Get-ADComputer $Using:VMName | Remove-ADObject -Recursive -Confirm:$False
        }
        $Error.Clear()
        If ($Error) {
            Write-BTRLog "Failed to remove AD account for $VmName. Error: $($Error[0].Exception.Message)" -Level Error
        }Else{
            Write-BTRLog "Removed AD account for $VmName." -Level Progress
        }
    }Else{
        Write-BTRLog "AD account for $VmName not found." -Level Debug
    } 

    Write-BTRLog "Exiting Delete-BTRVM" -Level Debug
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

    ##Make sure ISO exists
    #If (!(Test-Path $ExchangeISO)) {
    #    Read-Host "Can't find $ExchangeISO!"
    #    Return
    #}
    #
    ##Make sure VM Exists and is on
    #If (!(Hyper-V\Get-VM -Name $VMName)) {
    #    Read-Host "$VMName does not exist"
    #    Return
    #}ElseIf(!(Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {dir c:\})) {
    #    Read-Host "Unable to connect to $VMName"
    #    Return
    #}
    #
    ##Make sure there isn't already Exchange in the domain
    #If (Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {Get-AdGroup "Exchange Servers" -ErrorAction SilentlyContinue 2>&1 | Out-Null}) {
    #    Read-Host "Looks like you already have an exchange organiztion in $($Instance.Name)"
    #    Return
    #}
    #
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

    Install-BTRSofware -Name ".net 4.8" -Instance $Instance -VMName $VMName -WebLink "https://go.microsoft.com/fwlink/?linkid=208863" -Installer "ndp48-x86-x64-allos-enu.exe" -Args "/q /norestart"

    Install-BTRSofware -Name "Unified Communications Managed API 4.0 Runtime" -Instance $BeaterInstance -VMName Ex1 -WebLink "https://download.microsoft.com/download/2/C/4/2C47A5C1-A1F3-4843-B9FE-84C0032C61EC/UcmaRuntimeSetup.exe" -Installer "UcmaRuntimeSetup.exe" -Args "/passive /norestart"

    Install-BTRSofware -Name "Visual C++ Redistributable Packages for Visual Studio 2013" -Instance $BeaterInstance -VMName Ex1 -WebLink "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe" -Installer "vcredist_x64.exe" -Args "/passive /norestart"


    "Mounting EXchange ISO ($ExchangeISO)"
    Hyper-V\Add-VMDvdDrive -VMName $VMName -Path $ExchangeISO
    
        

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
        If (!($FWRules | Where DisplayName -Like �SQL Server�)) {
            New-NetFirewallRule -DisplayName �SQL Server� -Direction Inbound �Protocol TCP �LocalPort 1433 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like �SQL Admin Connection�)) {
            New-NetFirewallRule -DisplayName �SQL Admin Connection� -Direction Inbound �Protocol TCP �LocalPort 1434 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like �SQL Database Management�)) {
            New-NetFirewallRule -DisplayName �SQL Database Management� -Direction Inbound �Protocol UDP �LocalPort 1434 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like �SQL Service Broker�)) {
            New-NetFirewallRule -DisplayName �SQL Service Broker� -Direction Inbound �Protocol TCP �LocalPort 4022 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like �SQL Debugger/RPC�)) {
            New-NetFirewallRule -DisplayName �SQL Debugger/RPC� -Direction Inbound �Protocol TCP �LocalPort 135 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like �SQL Browser�)) {
            New-NetFirewallRule -DisplayName �SQL Browser� -Direction Inbound �Protocol TCP �LocalPort 2382 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like �SQL Server Browse Button Service�)) {
            New-NetFirewallRule -DisplayName �SQL Server Browse Button Service� -Direction Inbound �Protocol UDP �LocalPort 1433 -Action allow
        }
    }

    #Install SSMS
    Install-BTRSofware -Name "SQL Server Management Studio" -Instance $BeaterInstance -VMName DB1 -Installer "SSMS-Setup-ENU.exe" -WebLink 'https://aka.ms/ssmsfullsetup' -Args "/install /quiet /passive /norestart"
}

Function New-BtrUsers {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$NamingPattern,
        [Int64]$NumberOfUsers = 1,
        [String]$Password,
        [Switch]$CreateMailbox
    )

    Write-BTRLog "Enterning New-BtrUser" -Level Debug
    
    If (!($Password)) {
        Write-BTRLog "Password not specified, using default Instance password" -Level Debug
        $Password = $Instance.AdminPassword
    }

    Write-BTRLog "Checking if $Name Exists"
    If (Invoke-Command -VMName $Instance.DomainController -Credential $Using:Instance.DomainCreds -ScriptBlock { Get-ADUser $Using:Name }) {
        Write-BTRLog "$Name already exists" -Level Error
        Return
    }

    For ($I = 1; $I -le $NumberOfUsers; $I++) {
        
        Write-BTRLog "Creating "
    } 


}
