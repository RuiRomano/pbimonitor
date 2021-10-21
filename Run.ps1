$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

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

& .\FetchActivity.ps1 -config $config

& .\FetchCatalog.ps1 -config $config

& .\FetchGraph.ps1 -config $config

& .\FetchDataSetRefresh.ps1 -config $config