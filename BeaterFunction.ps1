
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
        }ElseIf($Key.GetValueKind($Name) -eq 'DWord') {
            [Bool]$Temp = $Key.GetValue($Name)
            $TempHash.add($Name, $Temp)
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
    #Write-BTRLog "Entering Write-BTRToRegistry" -Level Debug

    #Test if root exists
    If (!(Test-Path $Root -ErrorAction SilentlyContinue)) {
        Write-BTRLog "$Root does not exist." -Level Error
        Return $false
    }

    ForEach ($SubItem In $Item.GetEnumerator() | Where Value ) {
        If ($SubItem.Value.GetType().Name -in ('String','Int32')) {
            #Add new propperty
            If (!((Get-ItemProperty -Path "$Root" -ErrorAction SilentlyContinue | Select -ExpandProperty $SubItem.Key -ErrorAction SilentlyContinue) -eq $SubItem.Value)) {
                $Error.Clear()
                #Write-BTRLog "Adding to $Root $($Item.Key) = $($SubItem.Value)" -Level Debug
                New-ItemProperty -Path "$Root" -Name $SubItem.Key -Value $SubItem.Value -PropertyType "String" -Force -Confirm:$false -ErrorAction SilentlyContinue *>&1 | Out-Null
                If ($Error) {
                    Write-BTRLog "Can't add string value $Name to $Root. Error: $($Error[0].Exception.Message)." -Level Error
                    Return $false
                }Else{
                    #Write-BTRLog "Added to $Root $($Item.Key) = $($SubItem.Value)" -Level Debug
                }
            }
        } ElseIf ($SubItem.Value.GetType().Name -eq 'Boolean') {
            #Add new propperty
            If (!((Get-ItemProperty -Path "$Root" -ErrorAction SilentlyContinue | Select -ExpandProperty $SubItem.Key -ErrorAction SilentlyContinue) -eq $SubItem.Value)) {
                $Error.Clear()
                #Write-BTRLog "Adding to $Root $($Item.Key) = $($SubItem.Value)" -Level Debug
                New-ItemProperty -Path "$Root" -Name $SubItem.Key -Value $SubItem.Value -PropertyType "DWORD" -Force -Confirm:$false -ErrorAction SilentlyContinue *>&1 | Out-Null
                If ($Error) {
                    Write-BTRLog "Can't add string value $Name to $Root. Error: $($Error[0].Exception.Message)." -Level Error
                    Return $false
                }Else{
                    #Write-BTRLog "Added to $Root $($Item.Key) = $($SubItem.Value)" -Level Debug
                }
            }
        } ElseIf($SubItem.Value.GetType().Name -eq 'Hashtable') {
            $NewRoot = "$Root\$($SubItem.Key)"
            #Create Key
            If (!(Test-Path "$NewRoot" -ErrorAction SilentlyContinue)) {
                $Error.Clear()
                New-Item -Path $Root -Name $SubItem.Key -Force -Confirm:$false -ErrorAction SilentlyContinue *>&1 | Out-Null
                If ($Error) {
                    Write-BTRLog "Can't create $NewRoot. Error: $($Error[0].Exception.Message)." -Level Error
                    Return $false
                }Else{
                    #Write-BTRConfig "Created $($SubItem.Key)" -level Debug
                }
            }
            #Call Self for Hashtable
            Write-BTRToRegistry -Item $SubItem.Value -Root $NewRoot
        }    
    }

        #Write-BTRLog "Exiting Write-BTRToRegistry" -Level Debug
        Return $True
}


Function Wait-BTRVMOnline {
    Param (
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)]$Instance,
        [int64]$MaxWaitTime = 5,
        [int64]$RetryEvery = 10,
        [Switch]$WaitForLogin
    )

    #Figure out credentials
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $LocalCreds = New-Object -TypeName System.Management.Automation.PSCredential("$VMName\$($Instance.AdminName)",$SecurePassword)

    #Make sure VM Exists and is on
    If (!(Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return $False
    }

    Write-BTRLog "Connecting to $VMName with max wait time $MaxWaitTime minutes." -Level Debug
    $GiveUpAt = (Get-Date).AddMinutes($MaxWaitTime)
    Write-BTRLog "Will give up at $GiveUpAt." -Level Debug
    Do {
        $Error.Clear()
        $Test = Invoke-Command -VMName $VMName -Credential $LocalCreds -ErrorAction SilentlyContinue -ScriptBlock {Get-Verb}
        If ($Error) {
		    Write-BTRLog "Failed to connect to $VMName with PSRemoting. Error: $($Error[0].Exception.Message)." -Level Debug
            Write-BTRLog "Will try again in $RetryEvery seconds. " -Level Debug
            If ($(Get-Date) -ge $GiveUpAt) {
                Write-BTRLog "We've waited $MaxWaitTime minutes and not connected to $VMName.  Dying..." -Level Error
                Return $False
            }Else{
                $Error.Clear()
                Start-Sleep -Seconds $RetryEvery
            }
	    }Else{
            If ($WaitForLogin) {
                Write-BTRLog "Connected to $VMName with PSRemoting.  Now waiting for logon." -Level Debug
                Do {
                    $UserName = Invoke-Command -VMName $VMName -Credential $LocalCreds -ErrorAction SilentlyContinue -ScriptBlock { (Get-WmiObject Win32_ComputerSystem).Username }
                    If ($UserName) {
                        Write-BTRLog "User $UserName is logged into $VMName" -Level Progress
                        Return $True
                    }Else{
                        If ($(Get-Date) -ge $GiveUpAt) {
                            Write-BTRLog "We've waited $MaxWaitTime minutes and no one logged to $VMName.  Dying..." -Level Error
                            Return $False
                        }Else{
                            $Error.Clear()
                            Start-Sleep -Seconds $RetryEvery
                        }
                    }
                }While ($True)
            }Else{
                Write-BTRLog "Connected to $VMName with PSRemoting" -Level Progress
                Return $True
            }
        }
    } While ($True)
}

Function Wait-BTRVMOffline {
    Param (
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)]$Instance,
        [int64]$MaxWaitTime = 10,
        [int64]$RetryEvery = 3
    )

    #Figure out credentials
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $LocalCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminName,$SecurePassword)

    #Make sure VM Exists and is on
    If (!(Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return $False
    }

    Write-BTRLog "Waiting for $VMName to go offline with max wait time $MaxWaitTime minutes." -Level Debug
    $GiveUpAt = (Get-Date).AddMinutes($MaxWaitTime)
    Write-BTRLog "Will give up at $GiveUpAt." -Level Debug
    Do {
        $Error.Clear()
        $OS = Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {Get-Verb}
        If ($Error) {
            Write-BTRLog "$VMName is now offline" -Level Debug
            Return $True
	    }Else{  
            If ($(Get-Date) -ge $GiveUpAt) {
                Write-BTRLog "We've waited $MaxWaitTime minutes and $VMName is still online." -Level Error
                Return $False
            }Else{
                $Error.Clear()
                Start-Sleep -Seconds $RetryEvery
            }
        }
    } While ($True)
}

Function Wait-BTRVMReboot {
    Param (
        [Parameter(Mandatory=$True)][String]$VMName,
        [HashTable]$Instance,
        [int64]$MaxWaitTime = 10,
        [int64]$RetryEvery = 3,
        [Switch]$JoinedDomain
    )

    #Make sure VM Exists
    If (!($VM = Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return $False
    }

    #Figure out instance from VM
    If (!($Instance)) {
        $InstanceName = $VM.Notes | ConvertFrom-Json -ErrorAction SilentlyContinue | Select -ExpandProperty Instance
        Write-BTRLog "$VmName is member of $InstanceName." -Level Debug
        If (!($Instance = $BeaterConfig.Instances[$InstanceName])) {
            Write-BTRLog "Unable to find instance for $VmName" -Level Error
            Return $False
        }
    }

    #Figure out credentials
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $LocalCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminName,$SecurePassword)
    $DomainCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    Write-BTRLog "Getting start time on $VMName." -Level Debug
    $StartTime = Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {Get-Date}
    Write-BTRLog "  VMs time is $StartTime" -Level Debug

    Write-BTRLog "Waiting for $VMName to reboot." -Level Debug
    $GiveUpAt = (Get-Date).AddMinutes($MaxWaitTime)
    Write-BTRLog "   Will give up at $GiveUpAt." -Level Debug
    If ($JoinedDomain) {
        $UseCreds = $DomainCreds
    }Else{
        $UseCreds = $LocalCreds
    }
    Do {
        $Error.Clear()
        $LastReboot = Invoke-Command -VMName $VMName -Credential $UseCreds -ErrorAction SilentlyContinue -ScriptBlock {
            $OS = Get-WmiObject Win32_OperatingSystem
            $OS.ConvertToDateTime($OS.LastBootUpTime)
        }
        If ($Error) {
            Write-BTRLog "Failed to connect to $VMName.  Error: $($Error[0].Exception.Message)" -Level Error
            If ($(Get-Date) -ge $GiveUpAt) {
                Write-BTRLog "We've waited $MaxWaitTime minutes and $VMName is still offline." -Level Error
                Return $False
            }Else{
                $Error.Clear()
                Write-BTRLog "Sleeping for $RetryEvery seconds" -Level Debug
                Start-Sleep -Seconds $RetryEvery
            }
	    }Else{
            Write-BTRLog "Last reboot was at $LastReboot." -Level Debug
            If ($LastReboot -gt $StartTime) {
                Write-BTRLog "Reboot done." -Level Progress
                Return $True
            }Else{
                If ($(Get-Date) -ge $GiveUpAt) {
                    Write-BTRLog "We've waited $MaxWaitTime minutes and $VMName hasn't rebooted." -Level Error
                    Return $False
                }Else{
                    Write-BTRLog "Sleeping for $RetryEvery seconds" -Level Debug
                    $Error.Clear()
                    Start-Sleep -Seconds $RetryEvery
                }
            }
        }
    } While ($True)
}


Function Install-BTRSofware {
    Param (
        [String]$Name,
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)][String]$Installer,
        [String]$Args,
        [String]$WebLink,
        [String]$Tweaks,
        [Switch]$MSI
        
    )

    #Make sure VM exists
    If (!($VM = Hyper-V\Get-VM -ErrorAction SilentlyContinue | Where Name -EQ $VMName)) {
        "$VMName does not exist"
        Return $False
    }

    #Figure out Instance
    $InstanceName = $VM.Notes | ConvertFrom-Json -ErrorAction SilentlyContinue | Select -ExpandProperty Instance
    If (!($Instance = $BeaterConfig.Instances[$InstanceName])) {
        Write-BTRLog "Unable to find instance for $VmName" -Level Error
        Return $False
    }Else{
        Write-BTRLog "$VmName is member of $InstanceName." -Level Debug
    }

    #Figure out Base Image
    $BaseImageName = $VM.Notes | ConvertFrom-Json -ErrorAction SilentlyContinue | Select -ExpandProperty BaseImage
    If (!($BaseImage = $BeaterConfig.BaseImages[$BaseImageName])) {
        Write-BTRLog "Unable to find Base Image for $VmName" -Level Error
        Return $False
    }Else{
        Write-BTRLog "$VmName is based on $BaseImageName." -Level Debug
    }

    #Figure out password
    $Error.Clear()
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $LocalCreds = New-Object -TypeName System.Management.Automation.PSCredential("$VMName\$($Instance.AdminName)",$SecurePassword)
    If ($Error) {
        Write-BTRLog "Can't figure out local creditals. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }

    $HostPath = $Instance.WorkingFolder
    $HostFullPath = "$HostPath`\$Installer"
    $VMPath = $Instance.VMTempFolder
    $VMFullpath = "$VMPath`\$Installer"

    If (!($Name)) {
        $Name = $Installer
    }
    Write-BTRLog "Installing $Name" -Level Debug
    
    #Make sure destination folder exists
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        If (!(Test-Path $Using:VmPath)) {
            New-Item -Path $Using:VmPath -ItemType Directory -Force -Confirm:$False
        }
    }
    If ($Error) {
        Write-BTRLog "Can't create temp folder $VMPath on $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "Created temp folder $VMName on $VMName." -Level Debug
    }

    #If the installer is not in working folder, download it
    If (!(Test-Path $HostFullPath)) {
        If ($WebLink) {
            $Error.Clear()
            Invoke-WebRequest -Uri $WebLink -OutFile $HostFullPath -ErrorAction SilentlyContinue
            If ($Error) {
                Write-BTRLog "Can't download installer for $Name from $WebLink. Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }
        }Else{
            Write-BTRLog "If the installer isn't on the host, you must provide a download URL" -Level Error
            Return $False
        }
    }

    #Copy installer
    Write-BTRLog "Copying $HostFullPath to $VMFullpath on $VMName" -Level Progress 
    $Error.Clear()
    Hyper-V\Copy-VMFile -VMName $VMName -SourcePath $HostFullPath -DestinationPath $VMFullpath -FileSource Host -Force -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Can't copy installer for $Name to $VMName" -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }
        
    #Run installer
    $Error.Clear()
    If ($MSI) {
        Write-BTRLog "Running msiexec.exe /i $VMFullpath $Args /qn!" -Level Debug
        Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
            Start-Process "msiexec.exe"  -ArgumentList "/i $($Using:VMFullpath) $($Using:Args) /qn!" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }
    }Else{
        Write-BTRLog "Running $VMFullpath $Args" -Level Debug
        Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
            Start-Process -FilePath $Using:VMFullpath -ArgumentList $Using:Args -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }
    }
    If ($Error) {
        Write-BTRLog "Install for $Name failed. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success" -Level Debug
    }

    If ($Tweaks) {
        ForEach ($Tweak In $Tweaks) {
            Write-BTRLog "Executing `"$Tweak`"" -Level Debug
            $Error.Clear()
            Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
                . $Using:Tweak
            }
            If ($Error) {
                Write-BTRLog "Failed to execute `"$Tweak`". Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                Write-BTRLog "     Success!" -Level Debug
            }
        }
    }

    Return $True
}

Function Get-BtrNextIP {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    ) 
    
    #$SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    #$InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    #$IP = Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
    #    Get-DnsServerResourceRecord -ZoneName $using:Instance.DomainName | Where RecordType -EQ 'A' | Select -ExpandProperty RecordData | Select -ExpandProperty IPv4Address | Select -ExpandProperty IPAddressToString | Sort | Select -Last 1
    #}
    Write-BTRLog "Getting Last IP on switch $($Instance.SwitchName)" -Level Debug
    If ($IP = (Get-VM | Select -ExpandProperty NetworkAdapters | Where SwitchName -eq $Instance.SwitchName | Select -ExpandProperty IPAddresses) | Sort -Descending | Select -First 1) {
        Write-BTRLog "Last IP on switch is $IP" -Level Debug
    }Else{
        $IP = "$($Instance.IPPrefix).50"
    }

    Return

    Do {
        $Octets = $IP -split "\."
        $Octets[3] = [String]([Int]$Octets[3] + 1)
        Write-Host $Octets[3]
        If ([Int]$Octets[3] -gt 100) {
            Write-BTRLog "Unable to find available IP on $($Instance.SwitchName)" -Level Error
            Return $False
        }
        $IP = $Octets -join "."
        Write-BTRLog "Testing $IP"
    } Until (!(Test-Connection $IP -Quiet -Count 1 -ErrorAction SilentlyContinue))
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
        If ($WinVer -eq 2004) {
            $URL = "https://go.microsoft.com/fwlink/?linkid=2120254"
        } ElseIf ($Winver -in ("1903","1909")) {
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

    #Verify App Folder exists
    If (!(Test-Path $($Config.AppFolder))) {
        Write-BTRLog "$($Config.AppFolder) does not exist. Creating" -Level Debug
        $Error.Clear()
        New-Item $Config.AppFolder -ItemType "Directory" -Confirm:$False -Force | Out-Null
        If ($Error) {
            Write-BTRLog "Unable to create $($Config.AppFolder). Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }
    }Else{
        Write-BTRLog "$($Config.AppFolder) already exists" -Level Debug
    }

    #Verify Certificate Folder exists
    If (!(Test-Path $($Config.CertFolder))) {
        Write-BTRLog "$($Config.CertFolder) does not exist. Creating" -Level Debug
        $Error.Clear()
        New-Item $Config.CertFolder -ItemType "Directory" -Confirm:$False -Force | Out-Null
        If ($Error) {
            Write-BTRLog "Unable to create $($Config.CertFolder). Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }
    }Else{
        Write-BTRLog "$($Config.CertFolder) already exists" -Level Debug
    }

    #Verify Base Image Folder exists
    If (!(Test-Path $($Config.BaseImagePath))) {
        Write-BTRLog "$($Config.BaseImagePath) does not exist. Creating" -Level Debug
        $Error.Clear()
        New-Item $Config.BaseImagePath -ItemType "Directory" -Confirm:$False -Force | Out-Null
        If ($Error) {
            Write-BTRLog "Unable to create $($Config.BaseImagePath). Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }
    }Else{
        Write-BTRLog "$($Config.BaseImagePath) already exists" -Level Debug
    }

    Return $True
}

Function Configure-BTRInstance {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )
    Write-BTRLog "Entering Install-BTRInstance" -Level Debug

    #Create folders if they don't exist
    If (!(Test-Path $($Instance.AppFolder))) {
        Write-BTRLog "$($Instance.AppFolder) does not exist. Creating" -Level Debug
        New-Item $($Instance.AppFolder) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $($Instance.CertFolder))) {
        Write-BTRLog "$($Instance.CertFolder) does not exist. Creating" -Level Debug
        New-Item $($Instance.CertFolder) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $($Instance.HDDPath))) {
        Write-BTRLog "$($Instance.HDDPath) does not exist. Creating" -Level Debug
        New-Item $($Instance.HDDPath) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $Instance.SnapshotPath)) {
        Write-BTRLog "$($Instance.SnapshotPath) does not exist. Creating" -Level Debug
        New-Item $Instance.SnapshotPath -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $($Instance.VMPath))) {
        Write-BTRLog "$($Instance.VMPath) does not exist. Creating" -Level Debug
        New-Item $($Instance.VMPath) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }
    If (!(Test-Path $($Instance.WorkingFolder))) {
        Write-BTRLog "$($Instance.WorkingFolder) does not exist. Creating" -Level Debug
        New-Item $($Instance.WorkingFolder) -ItemType "Directory" -Confirm:$False -Force | Out-Null
    }

    #Create Network Switch
    Write-BTRLog "Checking if vSwitch $($Instance.SwitchName) exists." -Level Debug
    If (!(Hyper-V\Get-VMSwitch -ErrorAction SilentlyContinue | Where Name -eq $Instance.SwitchName)) {
        Write-BTRLog "$($Instance.SwitchName) does not exist." -Level Debug
        If ($Instance.UseNAT) {
            Write-BTRLog "Instance $($Instance.Name) is set to use NAT. Creating $($Instance.SwitchName) as an Internal Switch." -Level Progress
            $Error.Clear()
            Hyper-V\New-VMSwitch -SwitchName $Instance.SwitchName -SwitchType Internal
            If ($Error) {
                Write-BTRLog "Can't create new switch. Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                Write-BTRLog "Created vSwitch $($Instance.SwitchName) as Internal" -Level Debug
            }
        }Else{
            Write-BTRLog "Instance $($Instance.Name) is NOT set to use NAT. Creating $($Instance.SwitchName) as a Private Switch." -Level Progress
            $Error.Clear()
            Hyper-V\New-VMSwitch -SwitchName $Instance.SwitchName -SwitchType Private
            If ($Error) {
                Write-BTRLog "Can't create new switch. Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
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
                Return $False
            }Else{
                Write-BTRLog "Host NIC attached to $($Instance.SwitchName) is Index $Index." -Level Debug
            }
            $Error.Clear
            Write-BTRLog "Assigning $($Instance.Gateway) to host NIC with Index $Index." -Level Progress
            New-NetIPAddress -IPAddress $Instance.Gateway -PrefixLength $Instance.SubnetLength -InterfaceIndex $Index
            Write-BTRLog "Verifying $($Instance.Gateway) is assigned to host NIC with Index $Index." -Level Debug
            $Error.Clear()
            If ((!(Get-NetAdapter -ErrorAction SilentlyContinue | Where name -Like "*$($Instance.SwitchName)*" | Select -ExpandProperty ifIndex))) {
                Write-BTRLog "Can't set IP on instance switch. Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                Write-BTRLog "Verified Host NIC with Index $Index is assinged IP $($Instance.Gateway)" -Level Debug
            }
        }Else{
            Write-BTRLog "Host already has IP set for NIC attached to vSwitch $($Instance.SwitchName)." -Level Debug
        }


        #Setting network to private
        Write-BTRLog "Waiting for switch to identity itself" -Level Debug
        Do {
            Sleep -Seconds 1
        }Until((Get-NetConnectionProfile | Where InterfaceAlias -Like "*$($Instance.SwitchName)*" | select -ExpandProperty Name) -notlike 'Identifying*')
        
        Write-BTRLog "Checking if network is set to Private" -Level Debug
        If ($(Get-NetConnectionProfile | Where InterfaceAlias -Like "*$($Instance.SwitchName)*" | select -ExpandProperty NetworkCategory) -ne 'Private' ) {
            $Error.Clear()
            Get-NetConnectionProfile | Where InterfaceAlias -Like "*$($Instance.SwitchName)*" | Set-NetConnectionProfile -NetworkCategory Private 
            If ($Error) {
                Write-BTRLog "Unable to set network to private. Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                Write-BTRLog "Set network to Private" -Level Progress
            }
        }Else{
            Write-BTRLog "Network is already set to Private" -Level Debug
        }

        #Create NAT
        Write-BTRLog "Checking if a NAT exists for $($Instance.Name)." -Level Debug
        If (!(Get-NetNat | Where Name -eq "$($Instance.SwitchName)NAT")) {
            Write-BTRLog "NAT does not exist for $($Instance.Name). Creating" -Level Debug
            $Error.Clear()
            New-NetNat -Name "$($Instance.SwitchName)NAT" -InternalIPInterfaceAddressPrefix "$($Instance.IPPrefix).0/$($Instance.SubnetLength)"
            If ($Error) {
                Write-BTRLog "Can't create NAT. Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }
        }Else{
            Write-BTRLog "NAT already exists." -Level Debug
        }

    }Else{
        Write-BTRLog "Instance $($Instance.Name) is not set to use NAT.  Skipping host IP check." -Level Debug
    }
    Write-BTRLog "Exiting Configure-BTRInstance" -Level Debug

    Return $True
}

Function Delete-BTRInstance {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Switch]$DeleteVMs,
        [Switch]$DeleteFolders
    )

    #Deal with any VMs
    If ($VMs = Hyper-V\Get-VM | Select -ExpandProperty NetworkAdapters | Where SwitchName -like $Instance.SwitchName | Select -ExpandProperty VMName) {
        Write-BTRLog "$(VMs.Count) VMs found in instance." -Level Debug
        If ($DeleteVMs) {
            ForEach ($VM In $VMs) {
                Write-BTRLog "Deleting $VM." -Level Debug
                If (!(Delete-BTRVM -Instance $Instance -VmName $VM)) {
                    Write-BTRLog "Unable to delete $VM. Error: $($Error[0].Exception.Message)" -Level Error
                    Return $False
                }Else{
                    Write-BTRLog "   Success!" -Level Debug
                }
            }
        }Else{
            Write-BTRLog "Instance $($Instance.Name) still contains VMs" -Level Error
            Return $False
        }
    }

    #Clean up folders
    If ($DeleteFolders) {
        If (Test-Path $($Instance.HDDPath)) {
            Write-BTRLog "$($Instance.HDDPath) exists. Deleting." -Level Debug
            $Error.Clear()
            Remove-Item $($Instance.HDDPath) -Recurse -Confirm:$False -Force | Out-Null
            If ($Error) {
                Write-BTRLog "Failed to delete $($Instance.HDDPath). Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                    Write-BTRLog "   Success!" -Level Debug
            }
        }
        If (Test-Path $Instance.SnapshotPath) {
            Write-BTRLog "$($Instance.SnapshotPath) exists. Deleting" -Level Debug
            $Error.Clear()
            Remove-Item $Instance.SnapshotPath -Recurse -Confirm:$False -Force | Out-Null
            If ($Error) {
                Write-BTRLog "Failed to delete $($Instance.SnapshotPath). Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                    Write-BTRLog "   Success!" -Level Debug
            }
        }
        If (!(Test-Path $($Instance.VMPath))) {
            Write-BTRLog "$($Instance.VMPath) exists. Deleting" -Level Debug
            $Error.Clear()
            Remove-Item $($Instance.VMPath) -Recurse -Confirm:$False -Force | Out-Null
            If ($Error) {
                Write-BTRLog "Failed to delete $($Instance.VMPath). Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                    Write-BTRLog "   Success!" -Level Debug
            }
        }

        If (!(Test-Path $Instance.BasePath -ErrorAction SilentlyContinue)) {
            Write-BTRLog "$($Instance.BasePath) exists. Deleting" -Level Debug
            $Error.Clear()
            Remove-Item $($Instance.BasePath) -Recurse -Confirm:$False -Force | Out-Null
            If ($Error) {
                Write-BTRLog "Failed to delete $($Instance.BasePath). Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                    Write-BTRLog "   Success!" -Level Debug
            }
        }
    }

    #Remove NAT
    $NatName = "$($Instance.SwitchName)NAT"
    If (Get-NetNat | Where Name -eq $NatName) {
        Write-BTRLog "Deleting $NatName" -Level Debug
        $Error.Clear()
        Remove-NetNat -Name $NatName -Confirm:$False -ErrorAction SilentlyContinue
        If ($Error) {
            Write-BTRLog "Failed to remove NAT $NatName. Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }Else{
            Write-BTRLog "   Success!" -Level Debug
        }
    }Else{
        Write-BTRLog "NAT not configured."-Level Debug
    }

    #Remove Switch
    If (Hyper-V\Get-VMSwitch -ErrorAction SilentlyContinue | Where Name -eq $Instance.SwitchName) {
        Write-BTRLog "$($Instance.SwitchName) exists.  Deleting" -Level Debug
        $Error.Clear()
        Hyper-V\Remove-VMSwitch $Instance.SwitchName -Force -Confirm:$False -ErrorAction SilentlyContinue
        If ($Error) {
            Write-BTRLog "Failed to remove $($Instance.SwitchName). Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }
    }
    
    Return $True

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
                            <Path>D:\sources\install.wim</Path>
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
    Write-BTRLog "Running from $($BaseImage.OscdimgPath)." -level Debug
    $Args = "-m -o -u2 -udfver102 -bootdata:2#p0,e,b`"$ExtractFolder\boot\etfsboot.com`"#pEF,e,b`"$ExtractFolder\efi\microsoft\boot\efisys.bin`" `"$ExtractFolder`" $($BaseImage.CustomISO)"
        Write-BTRLog "With Arguments $Args" -level Debug
    $Error.Clear()
    Start-Process -FilePath $BaseImage.OscdimgPath -ArgumentList $Args  -Wait -WindowStyle Minimized -ErrorAction SilentlyContinue
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
    Return $True
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
        Return $False
    }Else{
        Write-BTRLog "$VMName does not exist" -Level Debug
    }

    Write-BTRLog "Creating $VMName" -Level Debug
    $Error.Clear()
    $VM = Hyper-V\New-VM -Name $VMName -MemoryStartupBytes 1024MB -Generation 2 -Path $Instance.VMPath -ErrorAction SilentlyContinue 
    If ($Error) {
        Write-BTRLog "Unable to Create $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    } Else {
        Write-BTRLog "Created $VMName." -Level Progress
    }

    Write-BTRLog "Setting CPU count and checkpoints on $VMName" -Level Debug
    $Error.Clear()
    Hyper-V\Set-VM -Name $VMName -ProcessorCount 3 -AutomaticCheckpointsEnabled:$False -Confirm:$False -CheckpointType Production -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to configure $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    } Else {
        Write-BTRLog "Configured $VMName." -Level Debug
    }

    Write-BTRLog "Connecting $VMName to vSwitch $($Instance.SwitchName)" -Level Debug
    $Error.Clear()
    Hyper-V\Connect-VMNetworkAdapter -VMName $VMName -SwitchName $Instance.SwitchName -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to connect $VMName to vSwitch $($Instance.SwitchName). Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    } Else {
        Write-BTRLog "Connected $VMName to vSwitch $($Instance.SwitchName)" -Level Debug
    }

    Write-BTRLog "Configuring Integration Services on $VMName" -Level Debug
    $Error.Clear()
    Hyper-V\Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to configure Integration Services on $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    } Else {
        Write-BTRLog "Configured Integration Services on $VMName" -Level Debug
    }

    Write-BTRLog "Creating HDD $($BaseImage.BaseImage)." -Level Debug
    $Error.Clear()
    Hyper-V\New-VHD -Path $BaseImage.BaseImage -Dynamic -SizeBytes 40GB -ErrorAction SilentlyContinue *>&1 | Out-Null
    If ($Error) {
        Write-BTRLog "Unable to create HDD $($BaseImage.BaseImage). Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    } Else {
        Write-BTRLog "Created HDD $($BaseImage.BaseImage)." -Level Debug
    }

    Write-BTRLog "Attaching HDD $($BaseImage.BaseImage) to $VMName" -Level Debug
    $Error.Clear()
    Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $BaseImage.BaseImage -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to attach HDD $($BaseImage.BaseImage) to $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    } Else {
        Write-BTRLog "Attached HDD $($BaseImage.BaseImage) to $VMName." -Level Debug
    }

    Write-BTRLog "Attaching DVD $($BaseImage.CustomISO) to $VMName" -Level Debug
    $Error.Clear()
    Hyper-V\Add-VMDvdDrive -VMName $VMName -Path $BaseImage.CustomISO -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to attach DVD $($BaseImage.CustomISO) to $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
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
        Return $False
    } Else {
        Write-BTRLog "Attached DVD $($BaseImage.CustomISO) to $VMName." -Level Debug
    }

    Write-BTRLog "Writing notes" -Level Progress
    $Config = @{}
    $Config.Add("Instance",$Instance.Name)
    $config.Add("BaseImage",$BaseImage.Name)
    $Notes = $Config | ConvertTo-Json
    $Error.Clear()
    Hyper-V\Set-VM -Name $VmName -Notes $Notes -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to set notes on VM. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    Return $True
}

Function Configure-BTRBaseImage {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)]$BaseImage
    )

    Write-BTRLog "Entering configure-BTRBaseImage" -Level Debug
    $VMName = $BaseImage.Name

    #Figure Creditials
    $Error.Clear()
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $LocalCreds = New-Object -TypeName System.Management.Automation.PSCredential("$VMName\$($Instance.AdminName)",$SecurePassword)
    If ($Error) {
        Write-BTRLog "Can't figure out local creditals. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }

    Write-BTRLog "Making sure $VMName exists" -Level Debug
    If (!(Hyper-V\Get-VM | Where Name -EQ $VMName)) {
        Write-BTRLog "$VMName does not exist" -Level Error
        Return $False
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
                Write-BTRLog "Next free IP is $IP" -Level Debug
            }
        }

        Write-BTRLog "Getting host DNS servers" -Level Debug
        $Error.Clear()
        $DNSServers = Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Where AddressFamily -eq 2 | Where ServerAddresses | Select -ExpandProperty ServerAddresses
        If ($Error) {
            Write-BTRLog "Unable to retreive host DNS servers. Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }Else{
            If (!($DNSServers)) {
                Write-BTRLog "Unable to retreive host DNS servers" -Level Error
                Return $False
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
            Return $False
        }Else{
            Write-BTRLog "VM $VMName has MAC address $MacAddress" -Level Debug
        }

        Write-BtrLog "Setting IP to $IP" -Level Debug
        $Error.Clear()
        Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock { 
            $IfIndex = Get-NetAdapter -ErrorAction SilentlyContinue | WHERE MacAddress -eq $Using:MacAddress | Select -ExpandProperty ifIndex
            New-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -IPAddress $Using:IP -PrefixLength $Using:Instance.SubnetLength -DefaultGateway $Using:Instance.Gateway
        }
        If($Error) {
            Write-BTRLog "Failed to set static IP to $IP. Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }Else{
            Write-BTRLog "Set static IP to $IP." -Level Progress
        }

        Write-BtrLog "configuring DNS" -Level Debug
        $Error.Clear()
        Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
            $IfIndex = Get-NetAdapter -ErrorAction SilentlyContinue | WHERE MacAddress -eq $Using:MacAddress | Select -ExpandProperty ifIndex
            Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $Using:DNSServers
            Set-DnsClient -InterfaceIndex $IfIndex -RegisterThisConnectionsAddress $False
        }
        If($Error) {
            Write-BTRLog "Failed to configure DNS. Error: $($Error[0].Exception.Message)" -Level Error
            Return $False
        }Else{
            Write-BTRLog "Configured DNS" -Level Progress
        }

    }Else{
        Write-BTRLog "Base Image is set to use DHCP." -Level Debug
    }

    Write-BtrLog "Disabling IPv6" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock { 
        Get-NetAdapter -ErrorAction SilentlyContinue | foreach { Disable-NetAdapterBinding -InterfaceAlias $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue }
    }
    If($Error) {
        Write-BTRLog "Failed to disable IPv6. Error: $($Error[0].Exception.Message)" -Level Debug
        Return $False
    }Else{
        Write-BTRLog "Disabled IPv6" -Level Progress
    }

    Write-BTRLog "Disabling IE Enhanced Security" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
        $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
        Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue
    }
    If($Error) {
        Write-BTRLog "Failed to disable IE Enhanced Security. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "Disabled IE Enhanced Security" -Level Progress
    }

    Write-BTRLog "Disabling annoying message about New Windows Admin Center" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotPopWACConsoleAtSMLaunch" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    If($Error) {
        Write-BTRLog "Failed to disable annoying message about New Windows Admin Center. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "   Success!" -Level Progress
    }

    Write-BTRLog "Enabling RDP"
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0 *>&1 | Out-Null
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
        (Get-WmiObject -class Win32_TSGeneralSetting -Namespace root\cimv2\terminalservices -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(1) *>&1 | Out-Null
    }
    If($Error) {
        Write-BTRLog "Failed to enable RDP. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "Enabled RDP" -Level Progress
    }

    Write-BTRLog "Setting Time Zone" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        Set-TimeZone -Id $Using:Instance.TimeZone
    }
    If($Error) {
        Write-BTRLog "Failed to set Time Zone. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "Set Time Zone to $($Instance.TimeZone)" -Level Progress
    }

    Write-BTRLog "Installing Optional Components" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        DISM /online /enable-feature /featurename:NetFX3 /all / Source:<drive>:\sources\sxs /LimitAcces *>&1 | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName TFTP -NoRestart -ErrorAction SilentlyContinue *>&1 | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName TelnetClient -NoRestart -ErrorAction SilentlyContinue *>&1 | Out-Null
    }
    If($Error) {
        Write-BTRLog "Failed to install Optional Components. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "Installed Optional Components." -Level Progress
    }

    Write-BTRLog "Installing Admin Tools" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        If ($(Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue ).ProductType -ne 1) {
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Feature-Tools-BitLocker
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Feature-Tools-BitLocker-RemoteAdminTool
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Feature-Tools-BitLocker-BdeAducExt
            Install-WindowsFeature -IncludeAllSubFeature RSAT-DataCenterBridging-LLDP-Tools
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Clustering
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Clustering-Mgmt
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Clustering-PowerShell
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Clustering-AutomationServer
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Clustering-CmdInterface
            Install-WindowsFeature -IncludeAllSubFeature RSAT-NLB
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Shielded-VM-Tools
            Install-WindowsFeature -IncludeAllSubFeature RSAT-SNMP
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Storage-Replica
            Install-WindowsFeature -IncludeAllSubFeature RSAT-WINS
            Install-WindowsFeature -IncludeAllSubFeature RSAT-AD-Tools
            Install-WindowsFeature -IncludeAllSubFeature RSAT-AD-PowerShell
            Install-WindowsFeature -IncludeAllSubFeature RSAT-ADDS
            Install-WindowsFeature -IncludeAllSubFeature RSAT-AD-AdminCenter
            Install-WindowsFeature -IncludeAllSubFeature RSAT-ADDS-Tools
            Install-WindowsFeature -IncludeAllSubFeature RSAT-ADLDS
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Hyper-V-Tools
            Install-WindowsFeature -IncludeAllSubFeature RSAT-RDS-Licensing-Diagnosis-UI
            Install-WindowsFeature -IncludeAllSubFeature RSAT-ADCS
            Install-WindowsFeature -IncludeAllSubFeature RSAT-ADCS-Mgmt
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Online-Responder
            Install-WindowsFeature -IncludeAllSubFeature RSAT-ADRMS
            Install-WindowsFeature -IncludeAllSubFeature RSAT-DHCP
            Install-WindowsFeature -IncludeAllSubFeature RSAT-DNS-Server
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Fax
            Install-WindowsFeature -IncludeAllSubFeature RSAT-File-Services
            Install-WindowsFeature -IncludeAllSubFeature RSAT-DFS-Mgmt-Con
            Install-WindowsFeature -IncludeAllSubFeature RSAT-FSRM-Mgmt
            Install-WindowsFeature -IncludeAllSubFeature RSAT-NFS-Admin
            Install-WindowsFeature -IncludeAllSubFeature RSAT-NPAS
            Install-WindowsFeature -IncludeAllSubFeature RSAT-Print-Services
            Install-WindowsFeature -IncludeAllSubFeature RSAT-RemoteAccess
            Install-WindowsFeature -IncludeAllSubFeature RSAT-RemoteAccess-Mgmt
            Install-WindowsFeature -IncludeAllSubFeature RSAT-RemoteAccess-PowerShell
            Install-WindowsFeature -IncludeAllSubFeature RSAT-VA-Tools -ErrorAction SilentlyContinue *>&1 | Out-Null
            Install-WindowsFeature -IncludeAllSubFeature GPMC -ErrorAction SilentlyContinue *>&1 | Out-Null
        }Else{
            #TODO: Figure out install for Win10
        }
    }
    If($Error) {
        Write-BTRLog "Failed to install Admin Tools. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "Installed Admin Tools." -Level Progress
    }
    
    Write-BTRLog "Creating $($Instance.VMTempFolder)" -Level Debug
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        If (!(Test-Path $Using:Instance.VMTempFolder)) {
            New-Item $Using:Instance.VMTempFolder -ItemType Directory -Force -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
        }
    }

    Write-BTRLog "Installing Certficates" -Level Debug
    $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate
    If (!($Certificates = Get-ChildItem $Instance.CertFolder -ErrorAction SilentlyContinue)) {
        Write-BTRLog "Can't get list of certificates to install." -Level Debug
        Return $False
    }Else{
        ForEach ($Certificate In $Certificates) {
            $DestinationPath = "$($Instance.VMTempFolder)\$($Certificate.Name)"
            $Cert.Import($Certificate.FullName)
            Copy-VMFile $VMName -SourcePath $Certificate.FullName -DestinationPath $DestinationPath -CreateFullPath -FileSource Host -Force
            If ($Cert.Issuer -eq $Cert.GetName()) {
                Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
                    Import-Certificate -Filepath $Using:DestinationPath -CertStoreLocation "Cert:\LocalMachine\Root" *>&1 | Out-Null
                }
            }Else{
                Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
                    Import-Certificate -Filepath $Using:DestinationPath -CertStoreLocation "Cert:\LocalMachine\CA" *>&1 | Out-Null
                }
            }
        }
    }

    #Install Apps
    Write-BTRLog "Copying apps over" -Level Progress
    ForEach ($File In Get-ChildItem $Instance.AppFolder) {
        Hyper-V\Copy-VMFile -Name $VMName -SourcePath $File.FullName -DestinationPath "C:\Temp\$($File.Name)" -CreateFullPath -FileSource Host -Force
    }
    
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        #Installing .Net 4.8
        If (Test-Path "C:\Temp\ndp48-x86-x64-allos-enu.exe") {
            Start-Process -FilePath "C:\Temp\ndp48-x86-x64-allos-enu.exe" -ArgumentList "/q /norestart" -Wait -NoNewWindow
        }
        
        #Installing Chrome
        If (Test-Path "C:\Temp\GoogleChromeStandaloneEnterprise64.msi") {
            Start-Process Msiexec.exe -ArgumentList '/i "C:\Temp\GoogleChromeStandaloneEnterprise64.msi" /qb!' -Wait
            Unregister-ScheduledTask -TaskName "GoogleUpdateTaskMachineCore" -Confirm:$False *>&1 | Out-Null
            Unregister-ScheduledTask -TaskName "GoogleUpdateTaskMachineUA" -Confirm:$False *>&1 | Out-Null
            Get-Service "gupdate" | Stop-Service -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
            Get-Service "gupdate" | Set-Service -StartupType Disabled -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
        }
    
        #Installing NotePad++
        If (Test-Path "C:\Temp\npp.*.Installer.exe") {
            Start-Process -FilePath "C:\Temp\npp.*.Installer.exe" -ArgumentList "/S" -Wait -NoNewWindow
	        Rename-Item -Path "C:\Program Files (x86)\Notepad++\updater" -NewName "updater_disabled" -Force -Confirm:$False
        }
        
        #Installing 7Zip
        If (Test-Path "C:\Temp\7z*.exe") {
            Start-Process -FilePath "C:\Temp\7z*.exe" -ArgumentList "/S" -Wait -NoNewWindow
        }
        
        #Installing Putty
        If (Test-Path "C:\Temp\Putty-*-Installer.msi") {
            "Putty found"
            $PuttyFile = Get-Item "C:\Temp\Putty-*-Installer.msi"
            Start-Process Msiexec.exe -ArgumentList "/i $PuttyFile /qb!" -Wait -NoNewWindow
        }
    
        #Installing WinSCP
        If (Test-Path "C:\Temp\WinSCP-*-Setup.exe") {
            Start-Process -FilePath "C:\Temp\WinSCP-*-Setup.exe" -ArgumentList "/Silent /Norestart /ALLUSERS" -Wait -NoNewWindow
	        Remove-Item "C:\Users\Public\Desktop\WinSCP.lnk" -Force -Confirm:$False
        }
    
        #Creating IE Shortucts
        $Shell = New-Object -ComObject Wscript.Shell
	    $Shortcut = $Shell.CreateShortcut("C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Internet Explorer.lnk")
	    $Shortcut.TargetPath = "C:\Program Files\internet explorer\iexplore.exe"
	    $Shortcut.WorkingDirectory = "%HOMEDRIVE%%HOMEPATH%"
	    $Shortcut.Description = "Finds and displays information and Web sites on the Internet."
	    $Shortcut.Save()
    
        #Creating RDP shortcut
        $Shell = New-Object -ComObject Wscript.Shell
	    $Shortcut = $Shell.CreateShortcut("C:\Users\Public\Desktop\Remote Desktop Connection.lnk")
	    $Shortcut.TargetPath = "%windir%\system32\mstsc.exe"
	    $Shortcut.WorkingDirectory = "%windir%\system32\"
	    $Shortcut.Description = "Use your computer to connect to a computer that is located elsewhere and run programs or access files."
	    $Shortcut.Save()
    }

    If ($BaseImage.UpdateSource) {
        Write-BTRLog "Configuring Updates" -Level Progress
        Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name "TargetGroup" -Value "SVDI" -Force -Confirm:$False *>&1 | Out-Null
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name "TargetGroupEnabled" -Value "1" -Force -Confirm:$False *>&1 | Out-Null
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -Value $Using:BaseImage.UpdateSource -Force -Confirm:$False *>&1 | Out-Null
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -Value $Using:BaseImage.UpdateSource -Force -Confirm:$False *>&1 | Out-Null
            Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -Value 1 -Force -Confirm:$False *>&1 | Out-Null
        }
    }

    Write-BTRLog "Installing Windows Update Module" -Level Progress
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        Set-ExecutionPolicy Unrestricted -Force -Confirm:$False *>&1 | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -Confirm:$False -Force -ErrorAction SilentlyContinue *>&1 | Out-Null
        Register-PSRepository -Default -InstallationPolicy Trusted -ErrorAction SilentlyContinue *>&1 | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module -Name PSWindowsUpdate -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
        Import-Module -Name PSWindowsUpdate
    }

    Write-BTRLog  "Rebooting" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        Restart-Computer -Force -Confirm:$False -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to restart computer. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }
    If (Wait-BTRVMReboot -VMName $VMName) {
        Write-BTRLog "$VMName has rebooted" -Level Progress
    }Else{
        Write-BTRLog "$VMName failed to reboot" -Level Error
        Return $False
    }

    Write-BTRLog "Checking for updates" -Level Progress
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        Get-WindowsUpdate -Confirm:$False -ErrorAction SilentlyContinue  *>&1 | Out-Null
    }
    
    Write-BTRLog  "Installing updates" -Level Progress
    Invoke-Command -VMName $VMName -Credential $LocalCreds -ScriptBlock {
        Install-WindowsUpdate -AcceptAll -AutoReboot *>&1 | Out-Null
    }

    Return $True
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
        Return $False
    }

    #Figure out creditials
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminName,$SecurePassword)

    Write-BTRLog "Optimizing .Net" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock { 
	    Start-Process $Env:WINDIR\microsoft.net\framework64\v4.0.30319\ngen.exe -ArgumentList "executequeueditems /force" -Wait
	    Start-Process $Env:WINDIR\microsoft.net\framework64\v4.0.30319\ngen.exe -ArgumentList "update /force" -Wait
    }
    If ($Error) {
        Write-BTRLog "Failed to optimize .Net. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Disabling Auto Update" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
	    Stop-Service -Name BITS -ErrorAction SilentlyContinue
	    Stop-Service -Name wuauserv -ErrorAction SilentlyContinue
	    Set-Service -Name BITS -StartupType Disabled -ErrorAction SilentlyContinue
	    Set-Service -Name wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
        takeown /F C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator /A /R *>&1 | Out-Null
        icacls C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator /grant Administrators:F /T *>&1 | Out-Null
        Get-ScheduledTask -TaskPath "\Microsoft\Windows\UpdateOrchestrator\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue *>&1 | Out-Null
        Get-ScheduledTask -TaskPath "\Microsoft\Windows\WindowsUpdate\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue *>&1 | Out-Null
        Remove-Item C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator\* -Force -Confirm:$False -Recurse -ErrorAction SilentlyContinue
        REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate /v WUServer /d https://localhost:8531 /t REG_SZ /f *>&1 | Out-Null
    }
    If ($Error) {
        Write-BTRLog "Failed to disable Auto updates. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Cleaning up junk" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Remove-Item "C:\Temp" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue 
        Remove-Item "C:\Windows\Temp\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Users\Administrator\Downloads\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Users\Administrator\Documents\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Users\Administrator\AppData\Local\Temp\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Prefetch\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Logs\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
        Clear-RecycleBin -Force -Confirm:$False
    }
    If ($Error) {
        Write-BTRLog "Failed to cleanup junk. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Deleting shadow copies" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
	    Set-Service VSS -StartupType Manual
	    Start-Service VSS
	    Start-Process VSSAdmin.exe -ArgumentList "Delete Shadows /All /Quiet" -Wait
	    Stop-Service VSS
	    Set-Service VSS -StartupType Disabled
    }
    If ($Error) {
        Write-BTRLog "Failed to delete shadow copies. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Purging all event logs" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
	    Get-WinEvent -ListLog * -Force -ErrorAction SilentlyContinue | % { Wevtutil.exe cl $_.logname }
    }
    If ($Error) {
        Write-BTRLog "Failed to purge event logs. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Defrag C:" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
	    Optimize-Volume -DriveLetter C -Defrag -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to defrag C:. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Deleting NICs" -Level Progress #2019 doesn't do this and it creates problems later
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Get-ChildItem -Path HKLM:\SYSTEM\CurrentControlSet\Control\Network\Interfaces -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to delete NICs (not always a bad thing. Error: $($Error[0].Exception.Message)" -Level Debug
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Running Sysprep" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
        Start-Process "C:\Windows\System32\Sysprep\sysprep.exe" -ArgumentList "/oobe /generalize /mode:vm /shutdown /quiet" -Wait -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to start sysprep. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }
    
    #Delete VM and leave disk
    Write-BTRLog "Waiting for VM to shutdown" -Level Progress
    $VM = Hyper-V\Get-VM -VMName $VMName
    Do {
        Start-Sleep 5
    } Until ($VM.State -eq "Off")

    Write-BTRLog "Deleting VM $VMName" -Level Progress
    $Error.Clear()
    Hyper-V\Remove-VM -Name $VMName -Force -Confirm:$False
    If ($Error) {
        Write-BTRLog "Failed to delete VM. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Optimizing vhd $($BaseImage.BaseImage)" -Level Progress
    $Error.Clear()
    Optimize-VHD -Path $BaseImage.BaseImage -Mode Full
    If ($Error) {
        Write-BTRLog "Failed to optimize vhd. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Write-BTRLog "Setting vhd $($BaseImage.BaseImage) to Read Only" -Level Progress
    $Error.Clear()
    Set-ItemProperty -Path $BaseImage.BaseImage -Name IsReadOnly -Value $True -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to set vhd to Read Only. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }


    Write-BTRLog "Deleting Install ISO $($BaseImage.CustomISO)" -Level Progress
    $Error.Clear()
    Remove-Item $BaseImage.CustomISO -Force -Confirm:$False -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to delete install ISO. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    $VMFolder = "$($Instance.VMPath)\$VMName"
    Write-BTRLog "Deleting VM folder $VMFolder" -Level Progress
    $Error.Clear()
    Remove-Item $VMFolder -Recurse -Force -Confirm:$False -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to delete $VMFolder. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }Else{
        Write-BTRLog "  Success!" -Level Debug
    }

    Return $True
}

Function Install-BTRDomain {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    Write-BTRLog "Installing Domain Controller role on $($Instance.DomainController)" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        Install-WindowsFeature -Name AD-Domain-Services -IncludeAllSubFeature -IncludeManagementTools -Confirm:$False -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to install Domain Controller role on $($Instance.DomainController). Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    Write-BTRLog "Creating Domain $($Instance.DomainName) on $($Instance.DomainController)" -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        $SecurePassword = ConvertTo-SecureString -AsPlainText $Using:Instance.AdminPassword -Force
        Install-ADDSForest -DomainMode 7 -ForestMode 7 -InstallDNS -Force -DomainName $Using:Instance.DomainName -SafeModeAdministratorPassword $SecurePassword -DomainNetbiosName $Using:Instance.NBDomainName -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to create $($Instance.DomainName). Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    Return $True
}

Function Configure-BTRDomain {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    $DNSServers = Get-DnsClientServerAddress | Where AddressFamily -eq 2 | Where ServerAddresses | Select -First 1 | Select -ExpandProperty ServerAddresses
    $DC = $Instance.DomainController

    #Set NIC to register in DNS
    Write-BTRLog "Setting NIC on $DC to register in DNS." -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        $NICs = Get-WmiObject "Win32_NetworkAdapterConfiguration where IPEnabled='TRUE'"
        ForEach ($Nic In $Nics) {
            $Nic.SetDynamicDNSRegistration($true) *>&1 | Out-Null
        }
    }
    If ($Error) {
        Write-BTRLog "Failed to set NIC to register in DNS. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Create Reverse Lookup Zone
    Write-BTRLog "Creating reverse lookup zone on $DC." -Level Progress
    $NetworkID = "$($Instance.IPPrefix).0/$($Instance.SubnetLength)"
    $Octets = $Instance.IPPrefix -split "\."
    $ZoneName = $Octets[2] + "." + $Octets[1] + "." + $Octets[0] + ".in-addr.arpa"
    Write-BTRLog "Zone name: $ZoneName." -Level Debug
    Write-BTRLog "Network ID: $NetworkID." -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        If (!(Get-DnsServerZone | Where ZoneName -like $Using:ZoneName)) {
            Add-DNSServerPrimaryZone -NetworkID $Using:NetworkID -ReplicationScope Forest -DynamicUpdate Secure  -Confirm:$False -ErrorAction SilentlyContinue
        }
    }
    If ($Error) {
        Write-BTRLog "Failed to create reverse lookup zone. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Setup Forwarders
    Write-BTRLog "Setting DNS forwarders on $DC." -Level Progress
    Write-BTRLog "Forwarders are: $DNSServers" -Level Debug
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        Set-DnsServerForwarder -UseRootHint $False -IPAddress $Using:DNSServers -EnableReordering $True -Confirm:$False -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to set DNS forwarders. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Remove root hints
    Write-BTRLog "Removing root hints from $DC." -Level Progress
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        Get-DnsServerRootHint | Remove-DnsServerRootHint -Confirm: $False -Force -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to remove root hints. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Set Aging/Scavanging
    Write-BTRLog "Setting Aging/Scavanging on all zones." -Level Progress
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        Set-DnsServerScavenging -ScavengingState $True -RefreshInterval 7.00:00:00 -NoRefreshInterval 7.00:00:00 -ApplyOnAllZones -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to set Aging/Scavanging on all zones. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Register DC in Reverse lookup zone
    Write-BTRLog "Registering $DC in reverse Zone." -Level Progress
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        IPConfig /registerDNS *>&1 | Out-Null
    }
    If ($Error) {
        Write-BTRLog "Failed to register DC in reverse zone. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    Return $True
}

Function SetUp-BTRDHCPServer {
    Param (
        [Parameter(Mandatory=$True)]$Instance
    )

    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)

    $DC = $Instance.DomainController

    #Resetting Static IP, if you don't do this, DHCP fails to bind sometimes
    Write-BTRLog "Getting VM Mac Address." -Level Debug
    $MacAddress = $(Hyper-V\Get-VMNetworkAdapter -VMName $DC -ErrorAction SilentlyContinue | Select -ExpandProperty MACAddress) -replace "([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])", '$1$2-$3$4-$5$6-$7$8-$9$10-$11$12'
    If ($MacAddress.Length -ne 17) {
        Write-BTRLog "Unable to get Mac address" -Level Error
        Return $False
    }Else{
        Write-BTRLog "VM $DC has MAC address $MacAddress" -Level Debug
    }
    Write-BTRLog "Setting NIC to use DHCP." -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $DC -Credential $InstanceCreds -ScriptBlock { 
        $IfIndex = Get-NetAdapter -ErrorAction SilentlyContinue | WHERE MacAddress -eq $Using:MacAddress | Select -ExpandProperty ifIndex
        Set-NetIPInterface -InterfaceIndex $IfIndex -Dhcp Enabled -ErrorAction SilentlyContinue
        Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $IfIndex -Confirm:$False -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed remove static IP. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }
    Write-BTRLog "Setting Static IP." -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $DC -Credential $InstanceCreds -ScriptBlock { 
        $IfIndex = Get-NetAdapter -ErrorAction SilentlyContinue | WHERE MacAddress -eq $Using:MacAddress | Select -ExpandProperty ifIndex
        New-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -IPAddress $Using:Instance.DomainControllerIP -PrefixLength $Using:Instance.SubnetLength -DefaultGateway $Using:Instance.Gateway *>&1 | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $Using:Instance.DomainControllerIP *>&1 | Out-Null
        Set-DnsClient -InterfaceIndex $IfIndex -RegisterThisConnectionsAddress $True *>&1 | Out-Null
    }
    If ($Error) {
        Write-BTRLog "Failed Set static IP. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Install DHCP role
    Write-BTRLog "Installing DHCP Role on $DC." -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $DC -Credential $InstanceCreds -ScriptBlock {
        Install-WindowsFeature -Name DHCP -IncludeAllSubFeature -IncludeManagementTools -Confirm:$False  *>&1 | Out-Null
    }
    If ($Error) {
        Write-BTRLog "Failed to install DHCP role. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    Write-BTRLog "Waiting for DHCP install to finalize." -Level Progress
    Start-Sleep 5

    #Adding DHCP security groups
    Write-BTRLog "Adding DHCP security groups." -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $DC -Credential $InstanceCreds -ScriptBlock {
        netsh dhcp add securitygroups
    }
    If ($Error) {
        Write-BTRLog "Failed to add DHCP security groups. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }
    
    #Restarting DHCP Service
    Write-BTRLog "Restarting DHCP." -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $DC -Credential $InstanceCreds -ScriptBlock {
        Restart-Service dhcpserver  *>&1 | Out-Null
    }
    If ($Error) {
        Write-BTRLog "Failed to restart DHCP service. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Authorize DHCP in Domain
    Write-BTRLog "Authorizing $DC for DHCP in AD." -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $DC -Credential $InstanceCreds -ScriptBlock {
        Add-DhcpServerInDC -DNSName $Using:Instance.DomainController -IPAddress $Using:Instance.DomainControllerIP  *>&1 | Out-Null
    }
    If ($Error) {
        Write-BTRLog "Failed to autorize $DC for DHCP. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Configure IPv4 options
    Write-BTRLog "Configuring IPv4 options." -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $DC -Credential $InstanceCreds -ScriptBlock {
        Set-DhcpServerSetting -ConflictDetectionAttempts 1
        Set-DhcpServerv4DnsSetting -DynamicUpdates "Always" -DeleteDnsRRonLeaseExpiry $True
    }
    If ($Error) {
        Write-BTRLog "Failed to set DHCP options. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Create Scope
    Write-BTRLog "Creating IPv4 DHCP scope." -Level Progress
    $Start = $Instance.IPPrefix + "." + $Instance.DHCPStart
    $End = $Instance.IPPrefix + "." + $Instance.DHCPStop
    $ScopeID = $Instance.IPPrefix + ".0"
    Write-BTRLog "Scope ID: $ScopeID.  from $Start to $End" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $DC -Credential $InstanceCreds -ScriptBlock {
        Add-DhcpServerv4Scope -Name $Using:Instance.Name -StartRange $Using:Start -EndRange $Using:End -SubnetMask $Using:Instance.SubnetMask -State Active -LeaseDuration "1.0:00:00" 
        Set-DhcpServerv4OptionValue -ScopeId $Using:ScopeID -DNSServer $Using:Instance.DomainControllerIP -DNSDomain $Using:Instance.DomainName -Router $Using:Instance.Gateway
    }
    If ($Error) {
        Write-BTRLog "Failed to create DHCP scope. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    #Disable annoying message to finish DHCP setup
    Write-BTRLog "Disabling warning message about DHCP setup." -Level Progress
    $Error.Clear()
    Invoke-Command -VMName $Instance.DomainController -Credential $InstanceCreds -ScriptBlock {
        Set-ItemProperty –Path registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager\Roles\12 –Name ConfigurationState –Value 2
    }
    If ($Error) {
        Write-BTRLog "Failed to set DHCP options. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }


    Return $True
}



Function New-BTRVMFromTemplate {
     Param (
        [Parameter(Mandatory=$True)][HashTable]$Instance,
        [Parameter(Mandatory=$True)][String]$VmName,
        [Parameter(Mandatory=$True)][HashTable]$BaseImage,
        [Int]$CPUCount = 3,
        [Int]$MemoryMB,
        [Int]$MemoryGB
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
        Write-BTRLog "Base Image $($BaseImage.BaseImage) does not exist!" -Level Error
        Return $False
    }

    If (Test-Path $HDDName) {
        Write-BTRLog "$HDDName already exists!" -Level Error
        Return $False
    }

    Write-BTRLog "Cloning $($BaseImage.BaseImage) to $HDDName" -Level Progress
    $Error.Clear()
    $HDD = Hyper-V\New-VHD -ParentPath $BaseImage.BaseImage -Path $HDDName -Differencing
    If ($Error) {
        Write-BTRLog "Unable to create clone of HDD. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }
    
    Write-BTRLog "Creating VM $VMName" -Level Progress
    $Error.Clear()
    $VM = Hyper-V\New-VM -Name $VMName -Generation 2 -VHDPath $HDDName -Path $Instance.VMPath
    If ($Error) {
        Write-BTRLog "Failed to create VM. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }
    
    Write-BTRLog "Configuring $VMName" -Level Progress
    $Error.Clear()
    Hyper-V\Set-VM -Name $VMName -ProcessorCount $CPUCount -AutomaticCheckpointsEnabled:$False -CheckpointType Production -Confirm:$False -SnapshotFileLocation $Instance.SnapShotPath
    Hyper-V\Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $True -StartupBytes $Memory
    Hyper-V\Connect-VMNetworkAdapter -VMName $VMName -SwitchName $Instance.SwitchName
    Hyper-V\Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"
    Hyper-V\Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
    If ($Error) {
        Write-BTRLog "Failed to configure VM. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    Write-BTRLog "Writing notes" -Level Progress
    $Config = @{}
    $Config.Add("Instance",$Instance.Name)
    $config.Add("BaseImage",$BaseImage.Name)
    $Notes = $Config | ConvertTo-Json
    $Error.Clear()
    Hyper-V\Set-VM -Name $VmName -Notes $Notes -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Failed to set notes on VM. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    Write-BTRLog "Powering ON $VMName. This is required to get a MAC address assigned." -Level Progress
    $Error.Clear()
    Hyper-V\Start-VM -Name $VMName -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to power on $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    } Else {
        Write-BTRLog "     Success!" -Level Debug
    }

    Write-BTRLog "Waiting 3 seconds to get a MAC address." -Level Progress
    Start-Sleep -Seconds 3

    Write-BTRLog "Powering OFF $VMName." -Level Progress
    $Error.Clear()
    Hyper-V\Stop-VM -Name $VMName -TurnOff -Force -Confirm:$False -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to power off $VMName. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    } Else {
        Write-BTRLog "     Success!" -Level Debug
    }

    Write-BTRLog "Verifying that MAC address got assigned" -Level Progress
    $Error.Clear()
    $Mac = Hyper-V\Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select -ExpandProperty MACAddress
    If ($Error) {
        Write-BTRLog "Unable to find Mac Address for $VMName." -Level Error
        Return $False
    }ElseIf (!($Mac -match '^([0-9A-Fa-f]{12})$')) {
        Write-BTRLog "Unable to find Mac Address for $VMName." -Level Error
        Return $False
    Else
        Write-BTRLog "     MAc address for $VMName is $Mac" -Level Debug
    }

    Return $True
}
    
Function Delete-BTRVM {
    Param (
        [Parameter(Mandatory=$True)][String]$VmName
    )

    Write-BTRLog "Entering Delete-BTRVM" -Level Debug
    
    If (!($VM = Hyper-V\Get-VM -Name $VmName -ErrorAction SilentlyContinue)) {
        Write-BTRLog "$VmName does not exist" -Level Error
        Return $False
    }

    #Figure out Instance
    $InstanceName = $VM.Notes | ConvertFrom-Json -ErrorAction SilentlyContinue | Select -ExpandProperty Instance
    Write-BTRLog "$VmName is member of $InstanceName." -Level Debug
    If (!($Instance = $BeaterConfig.Instances[$InstanceName])) {
        Write-BTRLog "Unable to find instance for $VmName" -Level Error
        Return $False
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
            Return $False
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
        Return $False
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
            Return $False
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
        Return $False
    }Else{
        Write-BTRLog "Deleted $VMPath" -Level Progress
    }

    #See if we need to do Domain cleanup
    If ($Instance.DomainController) {
        If ($Instance.DomainController -ne $VmName) {
            $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
            $InstanceCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)
            Write-BTRLog "Connecting to $($Instance.DomainController)."
            $Error.Clear()
            $DomainSession = New-PSSession -VMName $Instance.DomainController -Credential $InstanceCreds
            If ($Error) {
                Write-BTRLog "Failed to create PS Session on $($Instance.DomainController). Error: $($Error[0].Exception.Message)" -Level Error
                Return $False
            }Else{
                Write-BTRLog "Created PS Session to $($Instance.DomainController)" -Level Debug
            }

            #Remove from DNS and AD
            Write-BTRLog "Checking if $VmName is in DNS" -Level Debug
            $DNS = Invoke-Command -Session $DomainSession -ScriptBlock {
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
            If (Invoke-Command -Session $DomainSession -ScriptBlock { Try{ Get-ADComputer $Using:VMName -ErrorAction SilentlyContinue } Catch {  } }) {
                Write-BTRLog "Domputer account for $VmName exists.  Deleting." -Level Debug
                 $Error.Clear()
                Invoke-Command -Session $DomainSession -ScriptBlock {
                    Try{
                        Get-ADComputer $Using:VMName -ErrorAction SilentlyContinue | Remove-ADObject -Recursive -Confirm:$False
                    }Catch{
                        #Do Nothing
                    }
                }
                If ($Error) {
                    Write-BTRLog "Failed to remove AD account for $VmName. Error: $($Error[0].Exception.Message)" -Level Error
                }Else{
                    Write-BTRLog "Removed AD account for $VmName." -Level Progress
                }
            }Else{
                Write-BTRLog "AD account for $VmName not found." -Level Debug
            }
        }
    }

    Write-BTRLog "Exiting Delete-BTRVM" -Level Debug
    Return $True
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
        Write-BTRLog "Failed to create DNS record. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }

    Return $True
}

Function Apply-BTRVMCustomConfig {
    Param (
        [Parameter(Mandatory=$True)][HashTable]$Instance,
        [Parameter(Mandatory=$True)][String]$VMName,
        [String]$IpAddress,
        [Parameter(Mandatory=$True)]$BaseImage,
        [Bool]$JoinDomain = $True
    )

    $MacAddress = $(Hyper-V\Get-VMNetworkAdapter -VMName $VMname | Select -ExpandProperty MACAddress) -replace "([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])", '$1$2-$3$4-$5$6-$7$8-$9$10-$11$12'
    If ($MacAddress.Length -ne 17 -or $MacAddress -eq "00-00-00-00-00-00") {
        Write-BTRLog "Unable to retrive Mac address" -Level Error
        Return $false
    }Else{
        Write-BTRLog "Mac address for $VMName is $MacAddress." -Level Debug
    }

    $HDDName = "$($Instance.HDDPath)\$VMName-C.vhdx"

    Write-BTRLog "Mounting $HDDName" -Level Debug
    $Error.Clear()
    $DriveLetter = Mount-VHD -Path $HDDName -Passthru -ErrorAction SilentlyContinue | Get-Partition -ErrorAction SilentlyContinue | Where DriveLetter -ErrorAction SilentlyContinue | Select -ExpandProperty DriveLetter
    If ($Error) {
        Write-BTRLog "Unable to mount $HDDName. Error: $($Error[0].Exception.Message)." -Level Error
        Return $false
    }Else{
        Write-BTRLog "     Sucess!" -Level Debug
    }

    Write-BTRLog "Writing config file for $VMName" -Level Debug
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
    		</component>'

            If ($IpAddress) {
            $FileContent += '
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
        }

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
    
    Write-BTRLog "Dismounting $HDDName" -Level Progress
    $Error.Clear()
    Dismount-VHD -Path $HDDName -ErrorAction SilentlyContinue
    If ($Error) {
        Write-BTRLog "Unable to dismount $HDDName. Error: $($Error[0].Exception.Message)." -Level Error
        Return $false
    }Else{
        Write-BTRLog "     Success!" -Level Debug
    }

    Return $True
}


Function Tweak-BTRVMPostDeloy {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$VMName,
        [Bool]$UseDomainCreds = $True
    )

    If ($UseDomainCreds) {
        $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
        $Creds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)
    }Else{
        $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
        $Creds = New-Object -TypeName System.Management.Automation.PSCredential("$VMName\$($Instance.AdminName)",$SecurePassword)
    }

    Write-BTRLog "Disabling IPv6" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $Creds -ScriptBlock { 
        Get-NetAdapter | foreach { Disable-NetAdapterBinding -InterfaceAlias $_.Name -ComponentID ms_tcpip6 }
    }
    If ($Error) {
        Write-BTRLog "Failed to disable IPv6. Error: $($Error[0].Exception.Message)." -Level Error
        Return $false
    }Else{
        Write-BTRLog "     Sucess!" -Level Debug
    } 

    Write-BTRLog "Disabling Server Manager" -Level Debug
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $Creds -ScriptBlock {
        Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask
    }
    If ($Error) {
        Write-BTRLog "Failed to disable Server Manager. Error: $($Error[0].Exception.Message)." -Level Error
        Return $false
    }Else{
        Write-BTRLog "     Sucess!" -Level Debug
    }

    Return $True
}

Function Install-BTRExchange {
    Param (
        [Parameter(Mandatory=$True)][String]$VMName,
        [Parameter(Mandatory=$True)][String]$ExchangeISO,
        [String]$UpdateISO,
        [String]$PrereqPath,
        [Int64]$StoreSizeGB = 100,
        [Int64]$LogSizeGB = 50

    )

    #Make sure ISO exists
    If (!(Test-Path $ExchangeISO)) {
        Read-Host "Can't find $ExchangeISO!"
        Return $False
    }
    
    #Make sure VM Exists
    If (!($VM = Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return $False
    }
    
    #Figure out Instance
    $InstanceName = $VM.Notes | ConvertFrom-Json -ErrorAction SilentlyContinue | Select -ExpandProperty Instance
    If (!($Instance = $BeaterConfig.Instances[$InstanceName])) {
        Write-BTRLog "Unable to find instance for $VmName" -Level Error
        Return $False
    }Else{
        Write-BTRLog "$VmName is member of $InstanceName." -Level Debug
    }
    
    #Figure out password
    $Error.Clear()
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $DomainCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)
    If ($Error) {
        Write-BTRLog "Can't figure out local creditals. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }
    
    #Verify Server is not 2019
    If (Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {(([System.Environment]::OSVersion.Version).Build -gt 17000)}) {
        Read-Host "$VMName is running an incompatable version of Windows"
        Return $False
    }
    
    #Make sure there isn't already Exchange in the domain
    If (Invoke-Command -VMName $Instance.DomainController -Credential $DomainCreds -ScriptBlock {Try {Get-AdGroup "Exchange Servers" -ErrorAction SilentlyContinue 2>&1 | Out-Null}Catch{}}) {
        Read-Host "Looks like you already have an exchange org in $($Instance.Name)"
        Return $False
    }
    
    #Disable Realtime Scan.  If you don't do this it quadruples the time to complete
    Invoke-Command -VMName $Instance.DomainController -Credential $DomainCreds -ScriptBlock {
        Set-MpPreference -DisableRealtimeMonitoring $True -ErrorAction SilentlyContinue 2>&1 | Out-Null
    }
    #
    #"Creating M: Drive"
    #$Path = "$($Instance.HDDPath)\$VMName-M.vhdx"
    #Hyper-V\New-VHD -Path $Path -SizeBytes 100GB -Dynamic
    #Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $Path
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Get-Disk | Where PartitionStyle -eq RAW  | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize -DriveLetter M
    #    Format-Volume -DriveLetter M -FileSystem NTFS -NewFileSystemLabel "MailStore" -Confirm:$False -Force
    #}
    #
    #"Creating L: Drive"
    #$Path = "$($Instance.HDDPath)\$VMName-L.vhdx"
    #Hyper-V\New-VHD -Path $Path -SizeBytes 50GB -Dynamic
    #Hyper-V\Add-VMHardDiskDrive -VMName $VMName -Path $Path
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Get-Disk | Where PartitionStyle -eq RAW | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize -DriveLetter L
    #    Format-Volume -DriveLetter L -FileSystem NTFS -NewFileSystemLabel "MailLog" -Confirm:$False -Force
    #}
    #
    #Write-BTRLog "Installing UCM 4.0." -Level Debug
    #If (Install-BTRSofware -Name "Unified Communications Managed API 4.0 Runtime" -VMName Ex1 -WebLink "https://download.microsoft.com/download/2/C/4/2C47A5C1-A1F3-4843-B9FE-84C0032C61EC/UcmaRuntimeSetup.exe" -Installer "UcmaRuntimeSetup.exe" -Args "-q") {
    #    Write-BTRLog "     Success!!" -Level Debug
    #}Else{
    #    Write-BTRLog "Failed to install UCM 4.0." -Level Error
    #    Return $False
    #}
    #
    #Write-BTRLog "Installing VC++ Redistributable 2013." -Level Debug
    #If (Install-BTRSofware -Name "Visual C++ Redistributable Packages for Visual Studio 2013" -VMName Ex1 -WebLink "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe" -Installer "vcredist_x64.exe" -Args "/passive /norestart") {
    #    Write-BTRLog "     Success!!" -Level Debug
    #}Else{
    #    Write-BTRLog "Failed to install UCM 4.0." -Level Error
    #    Return $False
    #}
    #
    #Write-BTRLog "Installing Pre-Requisites" -Level Debug
    #$Components = @(
	#	"NET-Framework-45-Features",
	#	"RPC-over-HTTP-proxy",
	#	"Web-Mgmt-Console",
	#	"WAS-Process-Model",
	#	"Web-Asp-Net45",
	#	"Web-Basic-Auth",
	#	"Web-Client-Auth",
	#	"Web-Digest-Auth",
	#	"Web-Dir-Browsing",
	#	"Web-Dyn-Compression",
	#	"Web-Http-Errors",
	#	"Web-Http-Logging",
	#	"Web-Http-Redirect",
	#	"Web-Http-Tracing",
	#	"Web-ISAPI-Ext",
	#	"Web-ISAPI-Filter",
	#	"Web-Lgcy-Mgmt-Console",
	#	"Web-Metabase",
	#	"Web-Mgmt-Console",
	#	"Web-Mgmt-Service",
	#	"Web-Net-Ext45",
	#	"Web-Request-Monitor",
	#	"Web-Server",
	#	"Web-Stat-Compression",
	#	"Web-Static-Content",
	#	"Web-Windows-Auth",
	#	"Web-WMI",
	#	"Windows-Identity-Foundation"
	#)
    #ForEach ($Component In $Components) {
    #    Write-BTRLog "   Installing $Component" -Level Debug
    #    $Error.Clear()
    #    Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock { 
    #        Install-WindowsFeature $Using:Component -IncludeAllSubFeature -Confirm:$False -ErrorAction SilentlyContinue *>&1 | Out-Null
    #    }
    #    If ($Error) {
    #        Write-BTRLog "Failed to install $Component. Error: $($Error[0].Exception.Message)." -Level Error
    #        Return $False
    #    }Else{
    #        Write-BTRLog "      Sucess!" -Level Debug
    #    }
    #}
    
    #Mount ISO
    Write-BTRLog "Mounting Exchange ISO ($ExchangeISO)" -Level Progress
    $Error.Clear()
    Hyper-V\Add-VMDvdDrive -VMName $VMName -Path $ExchangeISO
    If ($Error) {
        Write-BTRLog "Failed to mount ISO. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "      Sucess!" -Level Debug
    }
    
    #Run Exchange Installer
    Write-BTRLog "Running Exchange Setup" -Level Progress
    $Args = @(
        "/IAcceptExchangeServerLicenseTerms",
        "/Mode:Install",
        "/Roles:mb,mt",
        "/CustomerFeedbackEnabled:False",
        "/DisableAMFiltering",
        "/OrganizationName:$($Instance.Name)Org"
    )
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock { 
        Start-Process -FilePath "D:\setup.exe" -ArgumentList $Using:Args -Wait -ErrorAction SilentlyContinue
    }
    If ($Error) {
        Write-BTRLog "Failed to install Exchange. Error: $($Error[0].Exception.Message)." -Level Error
        Return $False
    }Else{
        Write-BTRLog "      Sucess!" -Level Debug
    }
    
    Read-Host 'Hit any key to continue...'

    #Run Cumulative Update
    If ($UpdateISO) {
    
        #Switch ISOs
        Write-BTRLog "Change DVDs" -Level Progress
        $Error.Clear()
        Hyper-V\Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue | Set-VMDvdDrive -Path $UpdateISO -Confirm:$False -ErrorAction SilentlyContinue
        If ($Error) {
            Write-BTRLog "Failed to mount update ISO. Error: $($Error[0].Exception.Message)." -Level Error
            Return $False
        }Else{
            Write-BTRLog "      Sucess!" -Level Debug
        }
    
        #Run Exchange Cumulative Update
        Write-BTRLog "Running Exchange Update" -Level Progress
        $Args = @(
            "/IAcceptExchangeServerLicenseTerms",
            "/Mode:Upgrade"
        )
        $Error.Clear()
        Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock { 
            Start-Process -FilePath "D:\setup.exe" -ArgumentList $Using:Args -Wait -ErrorAction SilentlyContinue
        }
        If ($Error) {
            Write-BTRLog "Failed to update Exchange. Error: $($Error[0].Exception.Message)." -Level Error
            Return $False
        }Else{
            Write-BTRLog "      Sucess!" -Level Debug
        }
    }
    
    #Eject ISO
    Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue | Remove-VMDvdDrive -ErrorAction SilentlyContinue
    
    #Enable Realtime Scan
    Invoke-Command -VMName $Instance.DomainController -Credential $DomainCreds -ScriptBlock {
        Set-MpPreference -DisableRealtimeMonitoring $False -ErrorAction SilentlyContinue 2>&1 | Out-Null
    }
    
    #Disable Cyphers
    Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\DES 56/56" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\NULL" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 128/128]8" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 40/128" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 56/128" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 128/128" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 40/128" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 56/128" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 64/128" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168/168" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\Multi-Protocol Unified Hello\Client" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\Multi-Protocol Unified Hello\Server" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\PCT 1.0\Client" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\PCT 1.0\Server" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server" /v DisabledByDefault /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server" /v Enabled /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /v DisabledByDefault /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /v Enabled /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" /v DisabledByDefault /t REG_DWORD /d 0 /f 2>&1 | Out-Null
        REG ADD "HKLM\System\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" /v Enabled /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\Software\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        REG ADD "HKLM\Software\Microsoft\.NETFramework\v4.0.30319" /v SystemDefaultTlsVersions /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    }

    Return $True
}

Function Configure-BTRExchange {
    Param (
        [Parameter(Mandatory=$True)][String]$VMName,
        [String]$CertificateTemplateName = "BeaterWeb",
        [String]$MailDomains,
        [String]$Alias,
        [String]$Cnames,
        [String]$ExtraSans
    )

    #Make sure VM Exists
    If (!($VM = Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return $False
    }

    #Figure out Instance
    $InstanceName = $VM.Notes | ConvertFrom-Json -ErrorAction SilentlyContinue | Select -ExpandProperty Instance
    If (!($Instance = $BeaterConfig.Instances[$InstanceName])) {
        Write-BTRLog "Unable to find instance for $VmName" -Level Error
        Return $False
    }Else{
        Write-BTRLog "$VmName is member of $InstanceName." -Level Debug
    }

    #Figure out password
    $Error.Clear()
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $DomainCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)
    If ($Error) {
        Write-BTRLog "Can't figure out local creditals. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }

    $Domain = $Instance.DomainName
    $DNSName = "$VMName.$Domain"


    #Start PS Session
    $Error.Clear()
    $PSS = New-PSSession -VMName $VMName -Credential $DomainCreds
    If ($Error) {
        Write-BTRLog "Unable to connect establish PS session with $VMName" -Level Error
    }Else{
        Write-BTRLog "Connected PS session to $VMName" -Level Progress
    }

    #Import Exchange managment module
    $Error.Clear()
    Invoke-Command -Session $PSS  -ScriptBlock {
        If (!(Get-PSSnapin | Where Name -eq "Microsoft.Exchange.Management.PowerShell.SnapIn")) {
            Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn
        }
    }
    If ($Error) {
        Write-BTRLog "Failed to import Exchange management module" -Level Error
        Return $False
    }Else{
       Write-BTRLog "Exchange PS plugin loaded." -Level Debug
    }

    ##Move Mailbox to M: and L: drives
    #Write-BTRLog "Moving mail database to L: and M: drives" -Level Progress
    #Invoke-Command -Session $PSS -ScriptBlock {
    #    Get-MailBoxDatabase -Identity * | ForEach {Move-DatabasePath -Identity $_.Name -EdbFilePath "M:\$($_.Name)\$($_.Name).edb" -logFolderPath "L:\$($_.Name)\" -Force -ErrorAction SilentlyContinue -Confirm:$False}
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to move database files" -Level Error
    #    Return $False
    #}Else{
    #   Write-BTRLog "   Success!" -Level Debug
    #}
    #
    #
    #Create MX record
    If ($Alias) {
        $Cnames += $Alias
        $MailRecord = $Alias
    }Else{
        $MailRecord = $VMName
    }
    If ($MailRecord -like "*.$Domain") {
        $MailRecord = $MailRecord -replace ".$Domain",""
    }
    #Write-BTRLog "Creating MX record $MailRecord in $Domain" -Level Progress
    #$Error.Clear()
    #Invoke-Command -VMName $Instance.DomainController -Credential $DomainCreds -ScriptBlock {
    #    Add-DnsServerResourceRecordMX -Preference 10 -Name "." -MailExchange $Using:MailRecord -ZoneName $Using:Domain
    #}
    #If ($Error) {
    #    Write-BTRLog "   Failed. Error: $($Error[0].Exception.Message)." -Level Error
    #    Return
    #}Else{
    #    Write-BTRLog "   Success!" -Level Error
    #}
    #
    #Create CNAMEs records
    #If ($Cnames) {
    #    ForEach ($Cname In $Cnames) {
    #        If ($Cname -like "*.$Domain") {
    #            $AddMe = $Cname -replace ".$Domain",""
    #        }Else{
    #            $AddMe = $Cname
    #        }
    #        Write-BTRLog "Adding CNAME $AddMe to $Domain" -Level Progress
    #        $Error.Clear()
    #        Invoke-Command -VMName $Instance.DomainController -Credential $DomainCreds -ScriptBlock {
    #            Add-DnsServerResourceRecordCName -ZoneName $Using:Domain -Name $Using:AddMe -HostNameAlias $Using:DNSName
    #        }
    #        If ($Error) {
    #            Write-BTRLog "   Failed. Error: $($Error[0].Exception.Message)." -Level Error
    #            Return
    #        }Else{
    #            Write-BTRLog "   Success!" -Level Error
    #        }
    #    }
    #}
    #
    #
    ##Create Certificate
    #$Subject = "CN=$DNSName"
    #$SANS = @("$Alias","$Alias.$($Instance.DomainName)","$VMName","$VMName.$($Instance.DomainName)","$Domain")
    #Write-BTRLog "Creating certificate from template $CertificateTemplateName with Subject:" -Level Progress
    #Write-BTRLog "SANS: $SANS" -Level Debug
    #Invoke-Command -Session $PSS -ScriptBlock {
    #    Get-Certificate -Template $Using:CertificateTemplateName -Url LDAP: -SubjectName $Using:Subject -CertStoreLocation Cert:\LocalMachine\My\ -DnsName $Using:SANS
    #}
    #If ($Error) {
    #    Write-BTRLog "   Failed. Error: $($Error[0].Exception.Message)." -Level Error
    #    Return
    #}Else{
    #    Write-BTRLog "   Success!" -Level Error
    #}
    #
    ##Install Certificate
    #Write-BTRLog "Assigning certificate with Subject:$Subject to Exchange Services" -Level Progress
    #Invoke-Command -Session $PSS -ScriptBlock {
    #    Get-ExchangeCertificate | Where Subject -EQ $Using:Subject | Enable-ExchangeCertificate -Services IIS,SMTP,IMAP,POP -Force -Confirm:$False
    #}
    #If ($Error) {
    #    Write-BTRLog "   Failed. Error: $($Error[0].Exception.Message)." -Level Error
    #    Return
    #}Else{
    #    Write-BTRLog "   Success!" -Level Error
    #}

    ##configure Accepted Domains
    #ForEach ($MailDomain In $MailDomains) {
    #    Write-BTRLog "Adding accepted domain $MailRecord" -Level Progress
    #    Invoke-Command -Session $PSS -ScriptBlock {
    #        New-AcceptedDomain -Name $Using:MailRecord -DomainName $Using:MailDomain -DomainType Authoritative -Confirm:$False
    #    }
    #    If ($Error) {
    #        Write-BTRLog "   Failed to add accepted domain $MailDomain. Error: $($Error[0].Exception.Message)." -Level Error
    #        Return
    #    }Else{
    #        Write-BTRLog "   Success!" -Level Error
    #    }
    #}

    #Set Virtual Directory URLs
    Write-BTRLog "Setting Virtual Directory URLs" -Level Progress
    Invoke-Command -Session $PSS -ScriptBlock {
        Get-OwaVirtualDirectory -Server $env:COMPUTERNAME | Set-OwaVirtualDirectory -InternalUrl "https://$($Using:Alias)/OWA" -ExternalUrl "https://$($Using:Alias)/OWA"
        Get-EcpVirtualDirectory -Server $env:COMPUTERNAME | Set-EcpVirtualDirectory -InternalUrl "https://$($Using:Alias)/ECP" -ExternalUrl "https://$($Using:Alias)/ECP"
        Get-ActiveSyncVirtualDirectory -Server $env:COMPUTERNAME | Set-ActiveSyncVirtualDirectory -InternalUrl "https://$($Using:Alias)/Microsoft-Server-ActiveSync" -ExternalUrl "https://$($Using:Alias)/Microsoft-Server-ActiveSync"
        Get-OabVirtualDirectory -Server $env:COMPUTERNAME | Set-OabVirtualDirectory -InternalUrl "https://$($Using:Alias)/OAB" -ExternalUrl "https://$($Using:Alias)/OAB"
        Get-AutodiscoverVirtualDirectory -Server $env:COMPUTERNAME | Set-AutodiscoverVirtualDirectory -InternalUrl "https://$($Using:Alias)/Autodiscover/Autodiscover.xml" -ExternalUrl "https://$($Using:Alias)/Autodiscover/Autodiscover.xml"
        Get-WebServicesVirtualDirectory -Server $env:COMPUTERNAME | Set-WebServicesVirtualDirectory -InternalUrl "https://$($Using:Alias)/EWS/Exchange.asmx" -ExternalUrl "https://$($Using:Alias)/EWS/Exchange.asmx"
        Get-OutlookAnywhere | Set-OutlookAnywhere -InternalHostname $Using:Alias -ExternalHostname $Using:Alias -ExternalClientsRequireSsl $True -InternalClientsRequireSsl $True -ExternalClientAuthenticationMethod Negotiate
        Get-MapiVirtualDirectory | Set-MapiVirtualDirectory -InternalUrl "https://$($Using:Alias)/mapi" -ExternalUrl "https://$($Using:Alias)/mapi"
    }
    If ($Error) {
        Write-BTRLog "   Failed to configure Virtual Directories. Error: $($Error[0].Exception.Message)." -Level Error
        Return
    }Else{
        Write-BTRLog "   Success!" -Level Error
    }

    Remove-PSSession -Session $PSS

    Return $True
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
        If (!($FWRules | Where DisplayName -Like 'SQL Server')) {
            New-NetFirewallRule -DisplayName 'SQL Server' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like 'SQL Admin Connection')) {
            New-NetFirewallRule -DisplayName 'SQL Admin Connection' -Direction Inbound -Protocol TCP -LocalPort 1434 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like 'SQL Database Management')) {
            New-NetFirewallRule -DisplayName 'SQL Database Management' -Direction Inbound -Protocol UDP -LocalPort 1434 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like 'SQL Service Broker')) {
            New-NetFirewallRule -DisplayName 'SQL Service Broker' -Direction Inbound -Protocol TCP -LocalPort 4022 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like 'SQL Debugger/RPC')) {
            New-NetFirewallRule -DisplayName 'SQL Debugger/RPC' -Direction Inbound -Protocol TCP -LocalPort 135 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like 'SQL Browser')) {
            New-NetFirewallRule -DisplayName 'SQL Browser' -Direction Inbound -Protocol TCP -LocalPort 2382 -Action allow
        }
        If (!($FWRules | Where DisplayName -Like 'SQL Server Browse Button Service')) {
            New-NetFirewallRule -DisplayName 'SQL Server Browse Button Service' -Direction Inbound -Protocol UDP -LocalPort 1433 -Action allow
        }
    }

    ##Install SSMS
    #Install-BTRSofware -Name "SQL Server Management Studio" -VMName $VMName -Installer "SSMS-Setup-ENU.exe" -WebLink 'https://aka.ms/ssmsfullsetup' -Args "/install /quiet /passive /norestart"

    ##Patch SQL
    #"Enabling auto updates on $SQLUser a Local Admin on $VMname"
    #Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
    #    Set-Service -Name BITS -StartupType AutoMatic -ErrorAction SilentlyContinue
	#    Set-Service -Name wuauserv -StartupType AutoMatic -ErrorAction SilentlyContinue
    #    Start-Service -Name BITS -ErrorAction SilentlyContinue
	#    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    #    REG ADD HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate /v WUServer /d "https://HPWSUS01.hobbylobby.corp:8531" /t REG_SZ /f *>&1 | Out-Null
    #}
    #
    #Write-BTRLog "Checking for updates" -Level Progress
    #Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
    #    Get-WindowsUpdate -Confirm:$False -ErrorAction SilentlyContinue  *>&1 | Out-Null
    #}
    #
    #Write-BTRLog  "Installing updates" -Level Progress
    #Invoke-Command -VMName $VMName -Credential $InstanceCreds -ScriptBlock {
    #    Install-WindowsUpdate -AcceptAll -AutoReboot *>&1 | Out-Null
    #}

    Return $True

}

Function Install-BTRCertAuth {
    Param (
        [Parameter(Mandatory=$True)][String]$VMName
    )

    #Make sure VM Exists
    If (!($VM = Hyper-V\Get-VM -Name $VMName)) {
        Read-Host "$VMName does not exist"
        Return $False
    }

    #Figure out Instance
    $InstanceName = $VM.Notes | ConvertFrom-Json -ErrorAction SilentlyContinue | Select -ExpandProperty Instance
    If (!($Instance = $BeaterConfig.Instances[$InstanceName])) {
        Write-BTRLog "Unable to find instance for $VmName" -Level Error
        Return $False
    }Else{
        Write-BTRLog "$VmName is member of $InstanceName." -Level Debug
    }

    #Figure out password
    $Error.Clear()
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $DomainCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)
    If ($Error) {
        Write-BTRLog "Can't figure out local creditals. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }
    
    ##Install Web Server Role
    #Write-BTRLog "Installing Web Server role" -Level Progress
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Install-WindowsFeature -name Web-Server -IncludeManagementTools `
    #        -Confirm:$False -ErrorAction SilentlyContinue 2>&1 | Out-Null
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to install IIS role" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Installed IIS Role" -Level Progress
    #}
    #
    ##Create folder for CDP
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    New-Item -Path C:\PKI -ItemType Directory -Force -Confirm:$False 2>&1 | Out-Null
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to create C:\PKI" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Created C:\PKI" -Level Progress
    #}
    #
    ##Create PKI virtual folder
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    New-WebVirtualDirectory -Name PKI -Site "Default Web Site" `
    #        -PhysicalPath "C:\PKI" `
    #        -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to create PKI Virtual Folder" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Created PKI virtual folder" -Level Progress
    #}
    #
    ##Allow Double Escaping
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    C:\Windows\System32\inetsrv\appcmd set config /section:requestfiltering /allowdoubleescaping:true 2>&1 | Out-Null
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to configure double escaping" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Configured double escaping" -Level Error
    #
    #}
    #
    ##Create CNAME in DNS
    #$ZoneName = $Instance.DomainName
    #$PKiName = "$VMName`.$ZoneName"
    #$Error.Clear()
    #Invoke-Command -VMName $Instance.DomainController -Credential $DomainCreds -ScriptBlock {
    #    If (!(Get-DnsServerResourceRecord -ZoneName $Using:Zonename | Where HostName -like 'PKI')) {
    #        Add-DnsServerResourceRecordCName -ZoneName $Using:Zonename -Name "PKI" -HostNameAlias $Using:PKiName
    #    }
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to create CNAME for PKI" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Created CNAME for PKI" -Level Error
    #}
    #
    #
    ##Install CA Role
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Add-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools 2>&1 | Out-Null
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to install CA role" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Install CA role" -Level Progress
    #}
    #
    ##Setup CA Role
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Try {
    #        Install-AdcsCertificationAuthority `
    #            -CAType EnterpriseRootCA `
    #            -ValidityPeriodUnits 20 `
    #            -ValidityPeriod Years `
    #            -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
    #            -KeyLength 4096 `
    #            -HashAlgorithmName SHA256 `
    #            -Force `
    #            -Confirm:$False -ErrorAction SilentlyContinue 2>&1 | Out-Null
    #    }Catch{
    #        #Just to shut it up
    #    }
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to configure CA role" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Configued CA Role" -Level Progress
    #}
    #
    ##Configure CA in Registry
    #$Path = "HKLM:/SYSTEM/CurrentControlSet/Services/CertSvc/Configuration/$($Instance.NBDomainName)-$VMName-CA"
    #$CAPublish = @(
    #    "1:C:\Windows\system32\CertSrv\CertEnroll\%1_%3%4.crt",
    #    "2:http://PKI.$($Instance.DomainName)/PKI/%1_%3%4.crt",
    #    "2:ldap:///CN=%7,CN=AIA,CN=Public Key Services,CN=Services,%6%11"
    #)
    #$CRLPublish = @(
    #    "1:C:\Windows\system32\CertSrv\CertEnroll\%3%8%9.crl",
    #    "2:http://PKI.$($Instance.DomainName)/PKI/%3%8%9.crl",
    #    "10:ldap:///CN=%7%8,CN=%2,CN=CDP,CN=Public Key Services,CN=Services,%6%10",
    #    "65:file://C:\PKI\%3%8%9.crl"
    #)
    #
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    $Path = $Using:Path
    #    Get-Service | Where Name -eq certsvc | Stop-Service
    #    Start-Sleep 3
    #    Set-ItemProperty -Path $Path -Name CRLPeriodUnits -Value 3
    #    Set-ItemProperty -Path $Path -Name CRLPeriod -Value “Days”
    #    Set-ItemProperty -Path $Path -Name CRLDeltaPeriodUnits -Value 0
    #    Set-ItemProperty -Path $Path -Name CRLDeltaPeriod -Value “Days”
    #    Set-ItemProperty -Path $Path -Name CRLOverlapUnits -Value 3
    #    Set-ItemProperty -Path $Path -Name CRLPeriod -Value “Days”
    #    Set-ItemProperty -Path $Path -Name ValidityPeriodUnits -Value 2
    #    Set-ItemProperty -Path $Path -Name ValidityPeriod -Value “Years”
    #    Set-ItemProperty -Path $Path -Name AuditFilter -Value 127
    #    Set-ItemProperty -Path $Path -Name CACertPublicationURLs -Value $Using:CAPublish
    #    Set-ItemProperty -Path $Path -Name CRLPublicationURLs -Value $Using:CRLPublish
    #    Get-Service | Where Name -eq certsvc | Start-Service
    #    Start-Sleep 5
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to add CA config to registry" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Added CA config to registry" -Level Progress
    #}
    #
    ##Publish certificates and CRL
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Certutil -CRL  2>&1 | Out-Null
    #    Copy-Item C:\Windows\System32\certsrv\certenroll\* C:\PKI -Force
    #    $RootCertName = Get-Item -Path C:\Windows\System32\CertSrv\CertEnroll\* | Where Name -like "*CA.crt" |Select -ExpandProperty FullName
    #    Start-Process -FilePath C:\Windows\System32\certutil.exe -ArgumentList "-­f ­-dspublish $RootCertName RootCA" 2>&1 | Out-Null
    #    $RootCRLName = Get-Item -Path C:\Windows\System32\CertSrv\CertEnroll\* | Where Name -like "*CA.crl" |Select -ExpandProperty FullName
    #    Start-Process -FilePath C:\Windows\System32\certutil.exe -ArgumentList "-­f ­-dspublish $RootCRLName" 2>&1 | Out-Null
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to plush CA and CRL" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Published CA and CRL" -Level Progress
    #}
    
    ##Download PKI PS Module
    #If (!(Test-Path "$($Instance.WorkingFolder)\PSPKI")) {
    #    Write-BTRLog "PSPKI not downloaded.  Downloading." -Level Debug
    #    $Error.Clear
    #    Save-Module -Name PSPKI -Path $Instance.WorkingFolder -ErrorAction SilentlyContinue -Force
    #    If ($Error) {
    #        Write-BTRLog "  Failed to download PSPKI module" -Level Error
    #        Return $False
    #    }Else{
    #        Write-BTRLog "   Success!" -Level Progress
    #    }
    #}Else{
    #    Write-BTRLog "PSPKI has already been downloaded.  Using that" -Level Debug
    #}
    #
    ##Copy PSPKI to VM
    #Write-BTRLog "Copying PSPKI from $($Instance.WorkingFolder)\PSPKI to C:\Program Files\WindowsPowerShell\Modules\PSPKI on VM $VMName" -Level Debug
    #$Error.Clear
    #Get-ChildItem "$($Instance.WorkingFolder)\PSPKI" -Recurse -File | ForEach {Copy-VMFile -Name $VMName -SourcePath $_.FullName -DestinationPath $_.FullName.replace("C:\WSUS\Working","C:\Temp") -FileSource Host -CreateFullPath -Force }
    #If ($Error) {
    #    Write-BTRLog "  Failed to copy PSPKI module" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "   Success!" -Level Progress
    #}
    #
    ##Copy PKIPS to Modules folder
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Copy-Item -Path 'C:\Temp\PSPKI' -Destination 'C:\Program Files\WindowsPowerShell\Modules' -Recurse -Force -ErrorAction SilentlyContinue
    #}
    #If ($Error) {
    #    Write-BTRLog "  Failed to install PSPKI module" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "   Success!" -Level Progress
    #}

    #Create Web Server Template
    $TemplateName = "$($Instance.Name) Web"
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    $TemplateName = $Using:TemplateName
    #    $ConfigContext = ([ADSI]"LDAP://RootDSE").ConfigurationNamingContext 
    #    If (!(Test-Path "AD:\CN=$TemplateName,CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigContext" -ErrorAction SilentlyContinue )) {
    #
    #        #Figure out OIDs
    #        $ForestOID = Get-ADObject -Identity "CN=OID,CN=Public Key Services,CN=Services,$ConfigContext" -Properties msPKI-Cert-Template-OID | Select-Object -ExpandProperty msPKI-Cert-Template-OID
    #        $HexCharacters = '0123456789ABCDEF'
    #        Do {
    #            $CommonPart = Get-Random -Minimum 1000000 -Maximum 9999999
    #            [String]$HexPart = 0
    #            For ($I = 1; $I -le 32; $I++) {
    #                $HexPart += $HexCharacters.Substring((Get-Random -Minimum 0 -Maximum 15),1)
    #            }
    #            $TemplateOID = "$ForestOID.$(Get-Random -Minimum 10000000 -Maximum 99999999).$CommonPart"
    #            $OIDName = "$CommonPart.$HexPart"
    #        } until (!(Get-ADObject -SearchBase "CN=OID,CN=Public Key Services,CN=Services,$ConfigContext" -Filter {msPKI-Cert-Template-OID -eq $TemplateOID}))
    #
    #        #Create Certificate
    #        $ADSI = [ADSI]"LDAP://CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigContext"
    #        $CopyFrom = [ADSI]"LDAP://CN=WebServer,CN=Certificate Templates,CN=Public Key Services,CN=Services,$ConfigContext"
    #        $NewTempl = $ADSI.Create("pKICertificateTemplate", "CN=$TemplateName") 
    #        $NewTempl.SetInfo()
    #        
    #        #Configure Certificate
    #        $NewTempl.Put("flags", 131649)
    #        $NewTempl.Put("msPKI-Certificate-Application-Policy", "1.3.6.1.5.5.7.3.1")
    #        $NewTempl.Put("msPKI-Certificate-Name-Flag", "1")
    #        $NewTempl.Put("msPKI-Cert-Template-OID", $TemplateOID)
    #        $NewTempl.Put("msPKI-Enrollment-Flag", "0")
    #        $NewTempl.Put("msPKI-Minimal-Key-Size", "2048")
    #        $NewTempl.Put("msPKI-Private-Key-Flag", "101056784")
    #        $NewTempl.Put("msPKI-RA-Signature", "0")
    #        $NewTempl.Put("msPKI-Template-Minor-Revision", "4")
    #        $NewTempl.Put("msPKI-Template-Schema-Version", "4")
    #        $NewTempl.pKICriticalExtensions = "2.5.29.15"
    #        $NewTempl.pKIDefaultCSPs = @("1,Microsoft RSA SChannel Cryptographic Provider")
    #        $NewTempl.pKIDefaultKeySpec = 1
    #        $NewTempl.pKIExpirationPeriod = $CopyFrom.pKIExpirationPeriod
    #        $NewTempl.pKIExtendedKeyUsage = "1.3.6.1.5.5.7.3.1"
    #        $NewTempl.pKIKeyUsage =  $CopyFrom.pKIKeyUsage
    #        $NewTempl.pKIMaxIssuingDepth = 0
    #        $NewTempl.pKIOverlapPeriod = $CopyFrom.pKIOverlapPeriod
    #        $NewTempl.SetInfo()
    #
    #        #Create OID object
    #        $OtherAttributes = @{
    #            'flags' = [System.Int32]'1'
    #            'msPKI-Cert-Template-OID' = $TemplateOID
    #        }
    #        New-ADObject -Path "CN=OID,CN=Public Key Services,CN=Services,$ConfigContext" -OtherAttributes $OtherAttributes  -Name $OIDName -Type 'msPKI-Enterprise-Oid'
    #        
    #        #Grant Authenticated Users Enroll Rights
    #        $InheritedObjectType = [GUID]'00000000-0000-0000-0000-000000000000'
    #        $ObjectType = [GUID]'0e10c968-78fb-11d2-90d4-00c04f79dc55'
    #        $SID = (Get-ADGroup "Domain Users").SID
    #        
    #        $ACL = Get-ACL "AD:\$($NewTempl.distinguishedName)"
    #        $SID = (Get-ADGroup "Domain Computers").SID
    #        $ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule $SID, 'ExtendedRight', 'Allow', $ObjectType, 'None', $InheritedObjectType
    #        $ACL.AddAccessRule($ACE)
    #        $SID = (Get-ADGroup "Domain Controllers").SID
    #        $ACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule $SID, 'ExtendedRight', 'Allow', $ObjectType, 'None', $InheritedObjectType
    #        $ACL.AddAccessRule($ACE)
    #        Set-Acl "AD:\$($NewTempl.distinguishedName)" -AclObject $ACL
    #    }
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to create $TemplateName template" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Created $TemplateName template" -Level Error
    #}

    ##Add Template to CA
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    While (!(Get-CaTemplate | Where Name -like $Using:TemplateName)) {
    #        Add-CATemplate -Name $Using:TemplateName -Force -Confirm:$False
    #    }
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to install $TemplateName on $VMName" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Installed $TemplateName on $VMName" -Level Progress
    #}
    #
    ##Create Certifciate for web server
    #Write-BTRLog "Creating certificate for web server"
    #$Error.Clear()
    #Invoke-Command -VMName $Instance.DomainController -Credential $DomainCreds -ScriptBlock {
    #    Get-Certificate -Url "LDAP:" -Template "$($Using:Instance.Name) Web" -SubjectName "CN=PKI.$($Using:Instance.DomainName)" -DnsName @("PKI.$($Using:Instance.DomainName)","PKI","$($env:COMPUTERNAME).$($Using:Instance.DomainName)","$($env:COMPUTERNAME)") -CertStoreLocation Cert:\LocalMachine\My 2>&1 | Out-Null
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to get SSL Cert" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Retreived SSL cert for web server" -Level Progress
    #}

    ##Install Certificate Authority Web Enrollment
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Add-WindowsFeature ADCS-Web-Enrollment -IncludeManagementTools 2>&1 | Out-Null
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to install CA web Enrollment role" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Install CA Web Enrollment role" -Level Progress
    #}
    #
    ##Configure Certificate Authority Web Enrollment
    #$Error.Clear()
    #Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
    #    Try {
    #        Install-AdcsWebEnrollment -Confirm:$False -Force 
    #    }Catch{
    #        #Just to shut it up
    #    }
    #}
    #If ($Error) {
    #    Write-BTRLog "Failed to configure CA web Enrollment role" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "Configured CA Web Enrollment role" -Level Progress
    #}

    #Add port 443 binding for default web site
    Write-BTRLog "Adding SSL binding to default web site"
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
        Import-Module WebAdministration
        $Thumbprint = Get-ChildItem Cert:\LocalMachine\My | Where Subject -eq "CN=PKI.$($Using:Instance.DomainName)" | Select -ExpandProperty Thumbprint
        New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port 443 -Protocol "https"
        (Get-WebBinding -Name "Default Web Site" -Port 443 -Protocol "https").AddSslCertificate($Thumbprint, "my")
    }
    If ($Error) {
        Write-BTRLog "Failed to add SLL binding to default website" -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success" -Level Debug
    }

    #Require SSL on CertSrv folder
    Write-BTRLog "Adding SSL binding to default web site"
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
        $Thumbprint = Get-ChildItem Cert:\LocalMachine\My | Where Subject -eq "CN=PKI.$($Using:Instance.DomainName)" | Select -ExpandProperty Thumbprint
        Import-Module IISAdministration
        $ConfigSection = Get-IISConfigSection -SectionPath "system.webServer/security/access" -Location "Default Web Site/CertSrv"
        Set-IISConfigAttributeValue -AttributeName sslFlags -AttributeValue Ssl -ConfigElement $ConfigSection
    }
    If ($Error) {
        Write-BTRLog "Failed to add SLL binding to default website" -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success" -Level Debug
    }

    #redirect default to /CertSrv
    Write-BTRLog "Setting redirect to /CertSrv"
    $Error.Clear()
    Invoke-Command -VMName $VMName -Credential $DomainCreds -ScriptBlock {
        Import-Module IISAdministration
        Get-IISConfigSection -SectionPath "system.webServer/httpRedirect" -Location "Default Web Site" | Set-IISConfigAttributeValue -AttributeName enabled -AttributeValue $True
        Get-IISConfigSection -SectionPath "system.webServer/httpRedirect" -Location "Default Web Site" | Set-IISConfigAttributeValue -AttributeName destination -AttributeValue "https://pki.catest.local/CertSrv"
        Get-IISConfigSection -SectionPath "system.webServer/httpRedirect" -Location "Default Web Site" | Set-IISConfigAttributeValue -AttributeName childOnly -AttributeValue $False
    }
    If ($Error) {
        Write-BTRLog "Failed to add SLL binding to default website" -Level Error
        Return $False
    }Else{
        Write-BTRLog "     Success" -Level Debug
    }

    ##Copy PKI GPO
    #$GPOFolder = "$PSScriptRoot\CertificateAuthority\PKI GPO\"
    #Write-BTRLog "Copying PSPKI from $GPOFolder to C:\Temp" -Level Debug
    #$Error.Clear
    #Get-ChildItem $GPOFolder -Recurse -File | ForEach {Copy-VMFile -Name $VMName -SourcePath $_.FullName -DestinationPath $_.FullName.replace($GPOFolder,"C:\Temp\") -FileSource Host -CreateFullPath -Force }
    #If ($Error) {
    #    Write-BTRLog "  Failed to copy PKI GPO folder" -Level Error
    #    Return $False
    #}Else{
    #    Write-BTRLog "   Success!" -Level Progress
    #}


}


Function New-BtrUsers {
    Param (
        [Parameter(Mandatory=$True)]$Instance,
        [Parameter(Mandatory=$True)][String]$NamingPattern,
        [Int64]$NumberOfUsers = 1,
        [String]$Password,
        [Switch]$CreateMailbox,
        [String]$OU
    )

    Write-BTRLog "Enterning New-BtrUser" -Level Debug
    
    $VMName = $Instance.DomainController
    If (!($OU)) {
        $OU = "$($Instance.Name)Users"
    }

    If (!($Password)) {
        Write-BTRLog "Password not specified, using default Instance password" -Level Debug
        $Password = $Instance.AdminPassword
    }

    #Figure out password
    $Error.Clear()
    $SecurePassword = ConvertTo-SecureString -AsPlainText $Instance.AdminPassword -Force
    $DomainCreds = New-Object -TypeName System.Management.Automation.PSCredential($Instance.AdminNBName,$SecurePassword)
    If ($Error) {
        Write-BTRLog "Can't figure out domain creditals. Error: $($Error[0].Exception.Message)" -Level Error
        Return $False
    }

    #Start PS Session
    $Error.Clear()
    $PSS = New-PSSession -VMName $VMName -Credential $DomainCreds
    If ($Error) {
        Write-BTRLog "Unable to connect establish PS session with $VMName" -Level Error
    }Else{
        Write-BTRLog "Connected PS session to $VMName" -Level Progress
    }

    #Check if OU already exists
    $Error.Clear()
    If (Invoke-Command -Session $PSS -ScriptBlock {Get-ADOrganizationalUnit -Filter * | Where Name -eq $Using:OU}) {
        Write-BTRLog "$OU already exists" -Level Debug
    }Else{
        Write-BTRLog "Creating $OU" -Level Progress
        $Error.Clear()
        Invoke-Command -Session $PSS -ScriptBlock {
            New-ADOrganizationalUnit -Name $Using:OU -Confirm:$False -ErrorAction SilentlyContinue
        }
        If ($Error) {
            Write-BTRLog "Failed to create new OU $OU." -Level Error
            Return $False
        }Else{
            Write-BTRLog "   Success!"
        }
    }

    #Get full path to OU
    $Error.Clear()
    $OUName = Invoke-Command -Session $PSS -ScriptBlock {
        Get-ADOrganizationalUnit -Filter * | Where Name -like $Using:OU | select -First 1 -ExpandProperty DistinguishedName
    }
    If ($Error) {
        Write-BTRLog "Failed to get OU" -Level Error
        Return $False
    }Else{
        Write-BTRLog "Users will be created in $OUName" -Level Debug
    }

    #Find Exchange Server and connect
    If ($CreateMailbox) {
        Write-BTRLog "Finding Exchange server" -Level Debug
        $Error.Clear()
        If ($ExchangeServerName = Invoke-Command -Session $PSS -ScriptBlock { Get-ADGroupMember "Exchange Servers" | Where objectClass -eq 'computer' | Select -First 1 -ExpandProperty Name }) {
            $ExPSS = New-PSSession -VMName $ExchangeServerName -Credential $DomainCreds

            Invoke-Command -Session $ExPSS -ScriptBlock {
                If (!(Get-PSSnapin | Where Name -eq "Microsoft.Exchange.Management.PowerShell.SnapIn")) {
                    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn
                }
            }
            If ($Error) {
                Write-BTRLog "Failed to import Exchange management module" -Level Error
                Return $False
            }Else{
               Write-BTRLog "Exchange PS plugin loaded." -Level Debug
            }
        }Else{
            Write-BTRLog "Unable to open PS session on $ExchangeServerName" -Level Error
            Return $False
        }
    }
    
    
    #Create the users
    For ($I = 1; $I -le $NumberOfUsers; $I++) {
        $PaddedNumber = ([String]$I).PadLeft(4,'0')
        $UserName = "$NamingPattern$PaddedNumber"
        Write-BTRLog "Creating $UserName" -Level Debug
        
        Write-BTRLog "   Checking if $UserName Exists"
        If (Invoke-Command -Session $PSS -ScriptBlock { Get-ADUser -Filter * | Where Name -Eq $Using:UserName }) {
            Write-BTRLog "      $UserName already exists" -Level Error
            Continue
        }

        Write-BTRLog "   Creating $UserName" -Level Progress
        $Error.Clear()
        Invoke-Command -Session $PSS -ScriptBlock {
            $Name = $Using:UserName
            $Password = ConvertTo-SecureString -AsPlainText $Using:Password -Force
            New-ADUser -Name $Name -SamAccountName $Name -AccountPassword $Password -UserPrincipalName "$Name@$($Using:Instance.DomainName)" -Path $Using:OUName -enabled $True -Confirm:$False
        }
        If ($Error) {
            Write-BTRLog "Failed to create $UserName" -Level Error
            Continue
        }Else{
            Write-BTRLog "      Success!"
        }

        #Mail Enable user
        If ($CreateMailbox) {
            Write-BTRLog "   Creating mailbox" -Level Debug
            $Error.Clear()
            Invoke-Command -Session $ExPSS -ScriptBlock {
                Enable-MailBox -Identity $Using:UserName -Alias $Using:UserName  2>&1 | Out-Null
            }
            If ($Error) {
                Write-BTRLog "Failed to create mailbox for $UserName" -Level Error
                Continue
            }Else{
                Write-BTRLog "      Success!" -Level Debug
            }
        }   
    } 
}


Function Get-RandomHex {
    param ([int]$Length)
    $Hex = '0123456789ABCDEF'
    [string]$Return = $null
    For ($i=1;$i -le $length;$i++) {
        $Return += $Hex.Substring((Get-Random -Minimum 0 -Maximum 16),1)
    }
    Return $Return
}