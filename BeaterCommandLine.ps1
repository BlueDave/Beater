

#Global Variables
$RegRoot = 'HKLM:SOFTWARE\HobbyLobby\Beater'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$LogLevel = 'Debug'
$ConsoleLevel = 'Debug'

Function Configure-BTRServer {
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
        $BeaterConfig.add('RootPath', $Rootpath)
    }
}



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
        If ((Read-Host "ADK does not appear to be installed.  Do you wish to download and install it now? (y/n)") -eq 'y') {
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


        }Else{
            Write-BTRLog " You must install ADK to continue." -Level Debug
            Return $False
        }
    }
    Return $True
}

#Look for configuration
If (!($BeaterConfig = Read-BTRFromRegistry)) {
    $BeaterConfig = @{}
    If (Read-Host "Unable to read existing config. Would you like to configure for Beater now?" -Eq "y") {
        If (Configure-BTRServer -Config $BeaterConfig) {
            Write-BTRLog "Successfuly configured server for Beater" -Level Progress
        }Else{
            Write-BTRLog "Successfuly configured server for Beater" -Level Error
            Return
        }
    }
}



#Check for Valid Instance

#Build Instance config

#Validate Instace

#Build Instance

#Check for Valid Base Image

#Build Base Image config

#Validate Base Image

#Build Base Image

#Main menu