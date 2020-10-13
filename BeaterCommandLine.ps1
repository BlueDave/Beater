

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
        $BeaterConfig.add('RootPath', $Rootpath)
    }
}

Function Set-BTRInstanceConfig {
     Param (
        [Parameter(Mandatory=$True)]$Config
    )
}



#Look for configuration
If (!($BeaterConfig = Read-BTRFromRegistry -Root 'HKLM:SOFTWARE\HobbyLobby\Beater')) {
    $BeaterConfig = @{}
    If (Read-Host "Unable to read existing config. Would you like to input basic configuration now?" -Eq "y") {
        If (Set-BTRServerConfigr -Config $BeaterConfig) {
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
        
        


#Build Instance config

#Validate Instace

#Build Instance

#Check for Valid Base Image

#Build Base Image config

#Validate Base Image

#Build Base Image

#Main menu