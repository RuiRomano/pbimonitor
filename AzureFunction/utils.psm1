function Get-PBIMonitorConfig {
    [cmdletbinding()]
    param
    (
        [string]
        $currentPath
    )
        
    Write-Host "Building PBIMonitor Config from Azure Function Configuration"

    $appDataPath = $env:PBIMONITOR_AppDataPath

    if (!$appDataPath)
    {
        $appDataPath = "C:\home\data\pbimonitor"
    }

    $outputPath = $env:PBIMONITOR_DataPath

    if (!$outputPath)
    {
        $outputPath = "$($env:temp)\PBIMonitorData\$([guid]::NewGuid().ToString("n"))"
    }

    $scriptsPath = $env:PBIMONITOR_ScriptsPath                

    if (!$scriptsPath)
    {
        $scriptsPath = "C:\home\site\wwwroot\Scripts"
    }

    $environment = $env:PBIMONITOR_ServicePrincipalEnvironment

    if (!$environment)
    {
        $environment = "Public"
    }

    $stgAccountConnStr = $env:PBIMONITOR_StorageConnStr

    if (!$stgAccountConnStr)
    {
        $stgAccountConnStr = $env:AzureWebJobsStorage
    }   

    $config = @{
        "AppDataPath" = $appDataPath;
        "ScriptsPath" = $scriptsPath;
        "OutputPath" = $outputPath;
        "StorageAccountConnStr" = $stgAccountConnStr;
        "StorageAccountContainerName" = $env:PBIMONITOR_StorageContainerName;
        "StorageAccountContainerRootPath" = $env:PBIMONITOR_StorageRootPath;
        "ActivityFileBatchSize" = $env:PBIMONITOR_ActivityFileBatchSize;
        "FullScanAfterDays" = $env:PBIMONITOR_FullScanAfterDays;
        "CatalogGetInfoParameters" = $env:PBIMONITOR_CatalogGetInfoParameters;
        "CatalogGetModifiedParameters" = $env:PBIMONITOR_CatalogGetModifiedParameters;
        "ServicePrincipal" = @{
            "AppId" = $env:PBIMONITOR_ServicePrincipalId;
            "AppSecret" = $env:PBIMONITOR_ServicePrincipalSecret;
            "TenantId" = $env:PBIMONITOR_ServicePrincipalTenantId;
            "Environment" = $environment;
        }
    }
    
    Write-Host "AppDataPath: $appDataPath"
    Write-Host "ScriptsPath: $scriptsPath"
    Write-Host "OutputPath: $outputPath"       
    
    Write-Output $config

}