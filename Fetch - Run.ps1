$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

Write-Host "Current Path: $currentPath"

Set-Location $currentPath

$configFilePath = "$currentPath\Config-Test.json"

if (Test-Path $configFilePath)
{
    $config = Get-Content $configFilePath | ConvertFrom-Json

    # Default Values

    if (!$config.OutputPath)
    {        
        $config | Add-Member -NotePropertyName "OutputPath" -NotePropertyValue ".\\Data" -Force
    }

    if (!$config.ServicePrincipal.Environment)
    {
        $config.ServicePrincipal | Add-Member -NotePropertyName "Environment" -NotePropertyValue "Public" -Force           
    }
}
else
{
    throw "Cannot find config file '$configFilePath'"
}

try {
    & ".\Fetch - Activity.ps1" -config $config
    
    & ".\Fetch - Catalog.ps1" -config $config

    & ".\Fetch - Graph.ps1" -config $config

    & ".\Fetch - DataSetRefresh.ps1" -config $config
}
catch {

    $ex = $_.Exception

    if ($ex.ToString().Contains("429 (Too Many Requests)")) {
        Write-Host "429 Throthling Error - Need to wait before making another request..." -ForegroundColor Yellow
    }  

    Resolve-PowerBIError -Last

    throw    
}
