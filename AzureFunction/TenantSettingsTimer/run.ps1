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

    Write-Host "PBIMonitor - Fetch Tenant Settings Started: $currentUTCtime"
        
    Import-Module "$currentPath\..\utils.psm1" -Force

    $config = Get-PBIMonitorConfig $currentPath

    Import-Module "$($config.ScriptsPath)\Fetch - Utils.psm1" -Force
    
    New-Item -ItemType Directory -Path ($config.OutputPath) -ErrorAction SilentlyContinue | Out-Null
    
    & "$($config.ScriptsPath)\Fetch - Tenant Settings.ps1" -config $config
    
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
