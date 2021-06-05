#Requires -Modules @{ ModuleName="PowerBIPS"; ModuleVersion="2.0.4.11" }

param(        
    $outputPath = (".\Data\Catalog\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today),    
    $configFilePath = ".\Config.json",
    $reset = $false
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"

try
{
    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()


    $currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

    Set-Location $currentPath

    # ensure folder

    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null
    
    if (Test-Path $configFilePath)
    {
        $config = Get-Content $configFilePath | ConvertFrom-Json
    }
    else
    {
        throw "Cannot find config file '$configFilePath'"
    }

    $authToken = Get-PBIAuthToken -clientId $config.ServicePrincipal.AppId -clientSecret $config.ServicePrincipal.AppSecret -tenantId $config.ServicePrincipal.TenantId

    #region ADMIN API

    # Get workspaces + users (need this because users dont come in the async api)

    $filePath =  "$outputPath\workspaces.users.json" 

    if (!(Test-Path $filePath))
    {                
        $result = @(Invoke-PBIRequest -authToken $authToken -resource "groups" -odataParams "`$expand=users" -batchCount 5000 -admin)

        foreach ($item in $result)
        {
            $groupId = $item.id

            $items = $item.users

            $items | Add-Member -NotePropertyName groupId -NotePropertyValue $groupId -Force
        }

        $result.users | ConvertTo-Json -Depth 5 -Compress | Out-File $filePath

    }
    else
    {
        Write-Host "'filePath' file already exists"
    }

    $filePath = "$outputPath\apps.json"    

    if (!(Test-Path $filePath))
    {        
        $result = @(Invoke-PBIRequest -authToken $authToken -resource "apps" -odataParams "" -batchCount 5000 -admin)

        $result | ConvertTo-Json -Depth 5 -Compress | Out-File $filePath
    }
    else
    {
        Write-Host "'$filePath' already exists"
    }

    #endregion

    #region Workspace Scans: 1 - Get Modified; 2 - Start Scan for modified; 3 - Wait for scan finish; 4 - Get Results

    Write-Host "Getting workspaces to scan"

    $modifiedRequestUrl = "workspaces/modified"

    if ($config.Catalog.LastRun -and !$reset)
    {        
        $modifiedRequestUrl = $modifiedRequestUrl + "?modifiedSince=$($config.Catalog.LastRun)"
    }
    else
    {
        $config | Add-Member -NotePropertyName "Catalog" -NotePropertyValue @{"LastRun" = $null } -Force       
    }

    Write-Host "Reset: $reset"
    Write-Host "Since: $($config.Catalog.LastRun)"

    # Get Modified Workspaces since last scan

    $workspacesModified = Invoke-PBIRequest -authToken $authToken -resource $modifiedRequestUrl -admin

    if (!$workspacesModified)
    {
        Write-Host "No workspaces modified"
    }

    Write-Host "Modified workspaces: $($workspacesModified.Count)"

    $config.Catalog.LastRun = [datetime]::UtcNow.Date.ToString("o")

    $skip = 0
    $batchCount = 100
    $workspacesScanRequests = @()

    # Call GetInfo to request workspace scan in batches of 100 (throtling after 500 calls per hour) https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspaceinfo_postworkspaceinfo

    do
    {
        try
        {
            $workspacesBatch = @($workspacesModified | Select -First $batchCount -Skip $skip)

            if ($workspacesBatch)
            {
                Write-Host "Requesting workspace scan: $($skip + $batchCount) / $($workspacesModified.Count)"
    
                $bodyStr = @{"workspaces" = $workspacesBatch.Id } | ConvertTo-Json

                $getInfoDetails = "lineage=true&datasourceDetails=true&datasetSchema=true&datasetExpressions=true"

                $workspacesScanRequests += Invoke-PBIRequest -authToken $authToken -resource "workspaces/getInfo?$getInfoDetails" -body $bodyStr -admin -method Post -Verbose

                $skip += $batchCount            
            }
        }
        catch [System.Net.WebException]
        {
            $ex = $_.Exception

            $statusCode = $ex.Response.StatusCode

            if ($statusCode -eq 429)
            {                              
                $waitSeconds = [int]::Parse($ex.Response.Headers["Retry-After"])          

                Write-Host "429 Throthling Error - Need to wait $waitSeconds seconds..."

                Start-Sleep -Seconds ($waitSeconds + 5)

                $authToken = Get-PBIAuthToken -clientId $config.ServicePrincipal.AppId -clientSecret $config.ServicePrincipal.AppSecret -tenantId $config.ServicePrincipal.TenantId
            }
        }
    }
    while($workspacesBatch.Count -ne 0 -and $workspacesBatch.Count -ge $batchCount)

    # Wait for Scan to execute - https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspaceinfo_getscanstatus

    while(@($workspacesScanRequests |? status -in @("Running", "NotStarted")))
    {
        Write-Host "Waiting for scan results..."

        Start-Sleep -Seconds 5

        foreach ($workspaceScanRequest in $workspacesScanRequests)
        {
            $scanStatus = Invoke-PBIRequest -authToken $authToken -resource "workspaces/scanStatus/$($workspaceScanRequest.id)" -admin -method Get

            Write-Host "Scan '$($scanStatus.id)' : '$($scanStatus.status)'"

            $workspaceScanRequest.status = $scanStatus.status
        }
    }

    # Get Scan results (500 requests per hour) - https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspaceinfo_getscanresult

    $scansOutputPath = "$outputPath\scans"

    New-Item $scansOutputPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    foreach ($workspaceScanRequest in $workspacesScanRequests)
    {
        try
        {
            $scanResult = Invoke-PBIRequest -authToken $authToken -resource "workspaces/scanResult/$($workspaceScanRequest.id)" -admin -method Get

            Write-Host "Scan Result'$($scanStatus.id)' : '$($scanResult.workspaces.Count)'"

            $outputFilePath = "$scansOutputPath\$($workspaceScanRequest.id).json"

            $scanResult | Add-Member –MemberType NoteProperty –Name "scanCreatedDateTime"  –Value $workspaceScanRequest.createdDateTime -Force

            ConvertTo-Json $scanResult -Depth 10 -Compress | Out-File $outputFilePath -force
        }
        catch [System.Net.WebException]
        {
            $ex = $_.Exception

            $statusCode = $ex.Response.StatusCode

            if ($statusCode -eq 429)
            {                              
                $waitSeconds = [int]::Parse($ex.Response.Headers["Retry-After"])          

                Write-Host "429 Throthling Error - Need to wait $waitSeconds seconds..."

                Start-Sleep -Seconds ($waitSeconds + 5)                

                $authToken = Get-PBIAuthToken -clientId $config.ServicePrincipal.AppId -clientSecret $config.ServicePrincipal.AppSecret -tenantId $config.ServicePrincipal.TenantId
            }      
        }
    }

    ConvertTo-Json $config | Out-File $configFilePath -force

    #endregion

}
finally
{
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}