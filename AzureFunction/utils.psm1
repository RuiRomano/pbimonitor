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

    $containerName = $env:PBIMONITOR_StorageContainerName

    if (!$containerName)
    {
        $containerName = "pbimonitor"
    }

    $containerRootPath = $env:PBIMONITOR_StorageRootPath

    if (!$containerRootPath)
    {
        $containerRootPath = "raw"
    }

    $flagExtractGroups = $false

    if($env:PBIMONITOR_GraphExtractGroups)
    {
        $flagExtractGroups = [System.Convert]::ToBoolean($env:PBIMONITOR_GraphExtractGroups)
    }

    $config = @{
        "AppDataPath" = $appDataPath;
        "ScriptsPath" = $scriptsPath;
        "OutputPath" = $outputPath;
        "StorageAccountConnStr" = $stgAccountConnStr;
        "StorageAccountContainerName" = $containerName;
        "StorageAccountContainerRootPath" = $containerRootPath;
        "ActivityFileBatchSize" = $env:PBIMONITOR_ActivityFileBatchSize;
        "FullScanAfterDays" = $env:PBIMONITOR_FullScanAfterDays;
        "CatalogGetInfoParameters" = $env:PBIMONITOR_CatalogGetInfoParameters;
        "CatalogGetModifiedParameters" = $env:PBIMONITOR_CatalogGetModifiedParameters;
        "GraphPaginateCount" = $env:PBIMONITOR_GraphPaginateCount;
        "GraphExtractGroups" = $flagExtractGroups;
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