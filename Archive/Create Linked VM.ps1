
$VMFolder = "C:\VMs"
$SourceHDD = "Server2019-C.vhdx"
$VMName = "KMS1"

#$BeaterCreds = Get-Credential
#$BeaterZone = Invoke-Command -VMName DC1 -ScriptBlock {Get-DnsServerResourceRecord -ZoneName Beater.local} -Credential $BeaterCreds
#$LastIP = $BeaterZone | ? {$_.RecordType -eq 'A'} | Select -ExpandProperty RecordData | Select IPv4Address | Sort IPv4Address | Se

$CDrive = New-VHD -ParentPath "$VMFolder\$SourceHDD" -Path "$VMFolder\$VMName-C.vhdx" -Differencing


$VM = New-VM -Name $VMName -MemoryStartupBytes 1024MB -Generation 2 -VHDPath "$VMFolder\$VMName-C.vhdx"

Set-VM -Name $VMName -ProcessorCount 3 -AutomaticCheckpointsEnabled:$False -Confirm:$False

Connect-VMNetworkAdapter -VMName $VMName -SwitchName NAT

Set-VMFirmware -VMName $VMName -EnableSecureBoot Off

Start-VM -Name $VMName

#Invoke-Command -VMName $VMName -ScriptBlock {C:\Windows\system32\sysprep\sysprep.exe /generalize /reboot /oobe} -Cre


