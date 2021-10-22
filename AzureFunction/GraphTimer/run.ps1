#Requires -Modules @{ ModuleName="Az.Storage"; ModuleVersion="3.12.0" }

param($Timer)

try
{
    # Get the current universal time in the default string format.
    $currentUTCtime = (Get-Date).ToUniversalTime()
    
    if ($Timer.IsPastDue) {
        Write-Host "PowerShell timer is running late!"
    }

    Write-Host "PBIMonitor - Fetch Graph Started: $currentUTCtime"
        
    $appDataPath = $env:APPSETTING_PBIMONITOR_AppDataPath
    $outputPath = "$($env:temp)\PBIMonitorData\$([guid]::NewGuid().ToString("n"))"
    $scriptsPath = $env:APPSETTING_PBIMONITOR_ScriptsPath
    
    Import-Module "$scriptsPath\Fetch - Utils.psm1" -Force
    
    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "Output Path: $outputPath"
    
    $config = @{
        "OutputPath" = $outputPath;
        "ServicePrincipal" = @{
            "AppId" = $env:APPSETTING_PBIMONITOR_ServicePrincipalId;
            "AppSecret" = $env:APPSETTING_PBIMONITOR_ServicePrincipalSecret;
            "TenantId" = $env:APPSETTING_PBIMONITOR_ServicePrincipalTenantId;
            "Environment" = $env:APPSETTING_PBIMONITOR_ServicePrincipalEnvironment;
        }
    }
    
    $stateFilePath = "$appDataPath\state.json"
    
    & "$scriptsPath\Fetch - Graph.ps1" -config $config -stateFilePath $stateFilePath
    
    Write-Host "Writing to Blob Storage"
    
    $storageAccountConnStr = $env:APPSETTING_AzureWebJobsStorage
    $storageContainerName = "pbimonitor"
    $storageRootPath = "raw/graph"
    $dataFolderPath = "$outputPath\Graph"
    
    Add-FolderToBlobStorage -storageAccountConnStr $storageAccountConnStr -storageContainerName $storageContainerName -storageRootPath $storageRootPath -folderPath $dataFolderPath
    
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
