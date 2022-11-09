param(
    [string]$configFilePath = ".\Config.json"
    ,
    [array]$scriptsToRun = @(
        ".\Fetch - Activity.ps1"
        ".\Fetch - Catalog.ps1"
        ".\Fetch - Graph.ps1"
        #".\Fetch - DataSetRefresh.ps1"
    )
)

$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

Import-Module "$currentPath\Fetch - Utils.psm1" -Force

Write-Host "Current Path: $currentPath"

Write-Host "Config Path: $configFilePath"
if (Test-Path $configFilePath) {
    $config = Get-Content $configFilePath | ConvertFrom-Json

    # Default Values

    if (!$config.OutputPath) {        
        $config | Add-Member -NotePropertyName "OutputPath" -NotePropertyValue ".\\Data" -Force
    }

    if ($config.ServicePrincipal -and !$config.ServicePrincipal.Environment) {
        $config.ServicePrincipal | Add-Member -NotePropertyName "Environment" -NotePropertyValue "Public" -Force           
    }
}
else {
    throw "Cannot find config file '$configFilePath'"
}

# Ensure Folders for PBI Report

@("$($config.OutputPath)\Activity", "$($config.OutputPath)\Catalog", "$($config.OutputPath)\Graph") |% {
    New-Item -ItemType Directory -Path $_ -ErrorAction SilentlyContinue | Out-Null
}

try {

    foreach ($scriptToRun in $scriptsToRun)
    {        
        try {
            Write-Host "Running '$scriptToRun'"

            & $scriptToRun -config $config
        }
        catch {            
            Write-Error "Error on '$scriptToRun' - $($_.Exception.ToString())" -ErrorAction Continue            
        }   
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
