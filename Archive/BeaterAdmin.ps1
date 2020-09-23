
$VMFolder = "C:\VMs"
$SourceHDD = "Server2019-C.vhdx"
$VMName = "KMS1"
$NATName = "NAT"
$NATNetworkName = "NATNetwork"
$NATIP = "192.168.116"

Function CheckIfAdmin {
    "Making sure you're running as admin"
    $MyWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
    $MyWindowsPrincipal=New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
    $AdminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
    If (!($myWindowsPrincipal.IsInRole($adminRole))) {
	    If (Test-Path variable:global:psISE) {
		    "You must Launch PowerShell ISE as an admin"
            Read-Host "Hit Enter to continue"
            Exit
	}Else{
		$NewProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
	}
	    $NewProcess.Arguments = $myInvocation.MyCommand.Definition
	    $NewProcess.Verb = "runas"
	    [System.Diagnostics.Process]::Start($NewProcess)
	    Exit
    }
}

Function EnableHyperV {
    If (!($(Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All -Online).State -eq "Enabled")) {
        Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools
    }
}
        

Function ConfigureNAT {
    $HostIP = "$NATIP.1"

    If (Get-VMSwitch -Name $NATName -ErrorAction SilentlyContinue) {
        "$NATName already exists"
    }Else{
        New-VMSwitch -Name $NATName -SwitchType Internal
    }
    If (Get-NetIPAddress | WHERE IP -eq $HostIP) {
        "Host Nic already exists"
        $SwitchIndex = $(Get-NetAdapter | WHERE Name -like "*$NATName*").ifIndex
        New-NetIPAddress -IPAddress $HostIP -PrefixLength 24 -InterfaceIndex $SwitchIndex
    }
        #New-NetNat –Name "NATNetwork"

}


Function NewVMFromTemplate {
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
}




