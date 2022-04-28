#Requires -Modules Az.Storage

param($Timer)

$global:erroractionpreference = 1

try
{

    $currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)    

    # Get the current universal time in the default string format.
    $currentUTCtime = (Get-Date).ToUniversalTime()
    
    if ($Timer.IsPastDue) {
        Write-Host "PowerShell timer is running late!"
    }

    Write-Host "PBIMonitor - Fetch Activity Started: $currentUTCtime"
    
    Import-Module "$currentPath\..\utils.psm1" -Force

    $config = Get-PBIMonitorConfig $currentPath

    New-Item -ItemType Directory -Path ($config.OutputPath) -ErrorAction SilentlyContinue | Out-Null

    Import-Module "$($config.ScriptsPath)\Fetch - Utils.psm1" -Force

    $stateFilePath = "$($config.AppDataPath)\state.json"
    
    & "$($config.ScriptsPath)\Fetch - Activity.ps1" -config $config -stateFilePath $stateFilePath
    
    Write-Host "End"    
}
catch {

    $ex = $_.Exception

    if ($ex.ToString().Contains("429 (Too Many Requests)")) {
        throw "429 Throthling Error - Need to wait before making another request..."
    }  

    Resolve-PowerBIError -Last

    throw    
}
