$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$LogLevel = 'Debug'
$ConsoleLevel = 'Debug'

Import-Module Hyper-V


#$2019BaseImage = @{
#    Name = 'Server2019'
#    BaseImage = 'C:\WSUS\BaseImages\Server2019-C.vhdx'
#    InstallMedia = 'C:\Users\dkbluem1\Downloads\SW_DVD9_Win_Server_STD_CORE_2019_64Bit_English_DC_STD_MLF_X21-96581.ISO'
#    ImageIndex = 2
#    CustomISO = 'C:\WSUS\Working\Server2019-Install.ISO'
#    ProductKey = 'N69G4-B89J2-4G8F4-WWYCC-J464C'
#    UseWSUS = $True
#    UseDHCP = $False
#    UpdateSource = 'https://HPWSUS01.hobbylobby.corp:8531'
#    DisableAutoUpdates = $True
#    OptimizeDotNet = $False
#}
#
#$2016BaseImage = @{
#    Name = 'Server2016'
#    BaseImage = 'C:\WSUS\BaseImages\Server2016-C.vhdx'
#    InstallMedia = 'C:\Users\dkbluem1\Downloads\SW_DVD9_Win_Svr_STD_Core_and_DataCtr_Core_2016_64Bit_English_-2_MLF_X21-22843.ISO'
#    ImageIndex = 2
#    CustomISO = 'C:\WSUS\Working\Server2016-Install.ISO'
#    ProductKey = 'WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY'
#    UseWSUS = $True
#    USeDHCP = $True
#    UpdateSource = 'https://HPWSUS01.hobbylobby.corp:8531'
#    DisableAutoUpdates = $True
#    OptimizeDotNet = $False
#}
#
#$LTSCBaseImage = @{
#    Name = 'Win10LTSC'
#    BaseImage = 'C:\WSUS\BaseImages\Win10LTSC-C.vhdx'
#    InstallMedia = 'C:\Users\dkbluem1\Downloads\SW_DVD5_WIN_ENT_LTSC_2019_64BIT_English_-2_MLF_X22-05056.ISO'
#    ImageIndex = 1
#    CustomISO = 'C:\WSUS\Working\Win10LTSC-Install.ISO'
#    ProductKey = 'M7XTQ-FN8P6-TTKYV-9D4CC-J462D'
#    UseWSUS = $True
#    USeDHCP = $True
#    UpdateSource = 'https://HPWSUS01.hobbylobby.corp:8531'
#    DisableAutoUpdates = $True
#    OptimizeDotNet = $False
#}
#
#$BeaterInstance = @{
#    Host = "LHL315574"
#    Name = "Beater"
#    DomainName = "Beater.Local"
#    NBDomainName = "Beater"
#    IPPrefix = "192.168.116"
#    Gateway = "192.168.116.1"
#    SubnetMask = "255.255.255.0"
#    SubnetLength = "24"
#    UseDHCP = $True
#    DHCPStart = 100
#    DHCPStop = 200
#    AdminName = 'Administrator'
#    AdminNBName = "Beater\Administrator"
#    AdminPassword = 'P@ssw0rd99'
#    DomainController = 'DC1'
#    DomainControllerIP = "192.168.116.50"
#    HDDPath = "C:\WSUS\Virtual Hard Disks"
#    VMPath = "C:\WSUS\Virtual Machines"
#    SnapshotPath = "C:\WSUS\Snapshots"
#    WorkingFolder = 'C:\WSUS\Working'
#    CertFolder = 'C:\WSUS\Certificates'
#    AppFolder = 'C:\WSUS\Apps'
#    VMTempFolder = 'C:\Temp'
#    SwitchName = "Beater"
#    UseNAT = $True
#    TimeZone = "Central Standard Time"
#}
#
#$BeaterHost = @{
#    RootPath = "C:\WSUS"
#    OscdimgPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
#    Instances = @{
#        'Beater' = $BeaterInstance
#    }
#    BaseImages = @{
#        'Server2019' = $2019BaseImage
#        'Server2016' = $2016BaseImage
#        'Win10LTSC' = $LTSCBaseImage
#    }
#}
#
#$SecurePassword = ConvertTo-SecureString -AsPlainText $BeaterInstance.AdminPassword -Force
#$BeaterInstance.DomainCreds = New-Object -TypeName System.Management.Automation.PSCredential($BeaterInstance.AdminNBName,$SecurePassword)
#$BeaterInstance.LocalCreds = New-Object -TypeName System.Management.Automation.PSCredential($BeaterInstance.AdminName,$SecurePassword)


Function Get-BTRBaseImageConfig {
    Param (
        [Parameter(Mandatory=$True)]$ServerConfig,
        [Parameter(Mandatory=$True)]$Instance
    )





##OpenLogFile
#$LogFile = "$($BeaterInstance.WorkingFolder)\Beater.log"
#"`n`n`n`n" >> $LogFile
#"Start at $(Get-Date)" >> $LogFile

. "$(Split-Path -Parent -Path $MyInvocation.MyCommand.Definition)\BeaterFunction.ps1"


$BeaterConfig = Read-BTRFromRegistry -Root 'HKLM:SOFTWARE\HobbyLobby\Beater'

#Validate-BTRHostconfig -Config $BeaterConfig

#Validate-BTRHost -Config $BeaterConfig

#Set-BTRInstanceConfig -Config $BeaterConfig


#Install-BTREnvironment -Instance $BeaterInstance
#Install-BRTADK -BaseImage $2019BaseImage

#Create-BTRISO -BaseImage $2019BaseImage -Instance $BeaterInstance
#Create-BTRBaseVM -BaseImage $2019BaseImage -Instance $BeaterInstance
#Configure-BTRBaseImage -BaseImage $2019BaseImage -Instance $BeaterInstance
#Prep-BTRBaseImage -BaseImage $2019BaseImage -Instance $BeaterInstance

#Install-BTRDomain -Instance $BeaterInstance
#Configure-BTRDomain -Instance $BeaterInstance
#SetUp-BTRDHCPServer -Instance $BeaterInstance

#$ComputerName = 'DC2'
#New-BTRVMFromTemplate -Instance $BeaterInstance -VMName $ComputerName -BaseImage $2019BaseImage
#$IP = Get-NextIP -Instance $BeaterInstance
#Add-BtrDNSRecord -Instance $BeaterInstance  -RecordName $ComputerName -IPAddress $IP
#Apply-BTRVMCustomConfig -VMName $ComputerName -Instance $BeaterInstance -IpAddress $IP -JoinDomain $True -BaseImage $2019BaseImage
#Start-VM -Name $ComputerName
#Wait-BTRVMOnline -VMName $ComputerName -Instance $BeaterInstance
#Tweak-BTRVMPostDeloy -Instance $BeaterInstance -VMName $ComputerName
#[System.Windows.MessageBox]::Show('Done')

#Delete-BTRVM -Instance $BeaterInstance -VmName Win10LTSC

#Install-BTRSQL -Instance $BeaterInstance -VMName DB1 -SQLISO "C:\Users\dkbluem1\Downloads\SW_DVD9_NTRL_SQL_Svr_Standard_Edtn_2019Nov2019_64Bit_English_OEM_VL_X22-18928.ISO"

#Install-BTRExchange -Instance $BeaterInstance -VMName EX1 -PrereqPath "C:\WSUS\Apps" -ExchangeISO "C:\Users\dkbluem1\Downloads\SW_DVD5_WIN_ENT_LTSC_2019_64BIT_English_-2_MLF_X22-05056.ISO"
