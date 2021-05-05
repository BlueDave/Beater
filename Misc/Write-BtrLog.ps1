Function Write-BTRLog {
    Param (
        [Parameter(Mandatory = $True,ValueFromPipeline = $true)][String]$Entry,
        [ValidateSet('Error','Progress','FunctionProgress','Debug')][String]$Level = "Debug"
    )

    #FindLogFile
    If (!(Get-Variable LogFile -Scope Global)) {
        


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