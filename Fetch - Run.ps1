param(    
    [bool]$activity = $false
    ,
    [bool]$catalog = $false
    ,
    [bool]$graph = $false
    ,
    [bool]$datasetRefresh = $true
)


$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

Import-Module "$currentPath\Fetch - Utils.psm1" -Force

Write-Host "Current Path: $currentPath"

$configFilePath = "$currentPath\Config-RRMSFT.json"

if (Test-Path $configFilePath) {
    $config = Get-Content $configFilePath | ConvertFrom-Json

    # Default Values

    if (!$config.OutputPath) {        
        $config | Add-Member -NotePropertyName "OutputPath" -NotePropertyValue ".\\Data" -Force
    }

    if (!$config.ServicePrincipal.Environment) {
        $config.ServicePrincipal | Add-Member -NotePropertyName "Environment" -NotePropertyValue "Public" -Force           
    }
}
else {
    throw "Cannot find config file '$configFilePath'"
}

try {
    if ($activity) {
        & ".\Fetch - Activity.ps1" -config $config
    }
    if ($catalog) {
        & ".\Fetch - Catalog.ps1" -config $config
    }
    if ($graph) {
        & ".\Fetch - Graph.ps1" -config $config
    }
    if ($datasetRefresh) {
        & ".\Fetch - DataSetRefresh.ps1" -config $config
    }
}
catch {

    $ex = $_.Exception

    if ($ex.ToString().Contains("429 (Too Many Requests)")) {
        Write-Host "429 Throthling Error - Need to wait before making another request..." -ForegroundColor Yellow
    }  

    Resolve-PowerBIError -Last

    throw    
}
