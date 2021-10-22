#Requires -Modules @{ ModuleName="Az.Storage"; ModuleVersion="3.12.0" }

param($Timer)

try
{
    # Get the current universal time in the default string format.
    $currentUTCtime = (Get-Date).ToUniversalTime()
    
    if ($Timer.IsPastDue) {
        Write-Host "PowerShell timer is running late!"
    }

    Write-Host "PBIMonitor - Fetch Activity Started: $currentUTCtime"
        
    $appDataPath = $env:PBIMONITOR_AppDataPath
    $outputPath = $env:APPSETTING_PBIMONITOR_DataPath
    if (!$outputPath)
    {
        $outputPath = "$($env:temp)\PBIMonitorData\$([guid]::NewGuid().ToString("n"))"
    }
    $scriptsPath = $env:PBIMONITOR_ScriptsPath    
    $storageAccountConnStr = $env:AzureWebJobsStorage
    $storageContainerName = "pbimonitor"
    $storageRootPath = "raw/audit"
    $dataFolderPath = "$outputPath\Activity"
    $config = @{
        "OutputPath" = $outputPath;
        "ServicePrincipal" = @{
            "AppId" = $env:PBIMONITOR_ServicePrincipalId;
            "AppSecret" = $env:PBIMONITOR_ServicePrincipalSecret;
            "TenantId" = $env:PBIMONITOR_ServicePrincipalTenantId;
            "Environment" = $env:PBIMONITOR_ServicePrincipalEnvironment;
        }
    }
    
    Write-Host "Scripts Path: $scriptsPath"          
    Write-Host "Output Path: $outputPath"
        
    Import-Module "$scriptsPath\Fetch - Utils.psm1" -Force
    
    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null       
    
    $stateFilePath = "$appDataPath\state.json"
    
    & "$scriptsPath\Fetch - Activity.ps1" -config $config -stateFilePath $stateFilePath
    
    Write-Host "Writing to Blob Storage"   
    
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
