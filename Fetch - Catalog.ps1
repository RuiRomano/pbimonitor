#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt.Profile"; ModuleVersion="1.2.1026" }

param(               
    [psobject]$config
    ,
    [bool]$reset = $false
    ,
    [string]$stateFilePath
)

try
{
    Write-Host "Starting Power BI Catalog Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()   

    $outputPath = "$($config.OutputPath)\catalog"    
    
    if (!$stateFilePath)
    {
        $stateFilePath = "$($config.OutputPath)\state.json"
    }    

    if (Test-Path $stateFilePath) {
        $state = Get-Content $stateFilePath | ConvertFrom-Json
    }
    else {
        $state = New-Object psobject 
    }
    
    # ensure folders
    
    $scansOutputPath = Join-Path $outputPath ("scans\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)
    $snapshotOutputPath = Join-Path $outputPath ("snapshots\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)

    New-Item -ItemType Directory -Path $scansOutputPath -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $snapshotOutputPath -ErrorAction SilentlyContinue | Out-Null

    Write-Host "Getting OAuth Token"

    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)

    $pbiAccount = Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential -Environment $config.ServicePrincipal.Environment

    Write-Host "Login with: $($pbiAccount.UserName)"

    #region ADMIN API    

    $filePath = "$snapshotOutputPath\apps.json"    

    if (!(Test-Path $filePath))
    {     
        Write-Host "Getting Power BI Apps List"
        
        $result = Invoke-PowerBIRestMethod -Url "admin/apps?`$top=5000&`$skip=0 " -Method Get | ConvertFrom-Json

        $result = @($result.value)

        if ($result.Count -ne 0)
        {
            ConvertTo-Json $result -Depth 10 -Compress | Out-File $filePath -force
        }
        else {
            Write-Host "Tenant without PowerBI apps"
        }
    }
    else
    {
        Write-Host "'$filePath' already exists"
    }

    #endregion

    #region Workspace Scans: 1 - Get Modified; 2 - Start Scan for modified; 3 - Wait for scan finish; 4 - Get Results

    Write-Host "Getting workspaces to scan"

    $modifiedRequestUrl = "admin/workspaces/modified"

    if ($state.Catalog.LastRun -and !$reset)
    {        
        if (!($state.Catalog.LastRun -is [datetime]))
        {
            $state.Catalog.LastRun = [datetime]::Parse($state.Catalog.LastRun).ToUniversalTime()
        }

        $modifiedRequestUrl = $modifiedRequestUrl + "?modifiedSince=$($state.Catalog.LastRun.ToString("o"))"
    }
    else {
        $state | Add-Member -NotePropertyName "Catalog" -NotePropertyValue @{"LastRun" = $null} -Force
    }

    Write-Host "Reset: $reset"
    Write-Host "Since: $($state.Catalog.LastRun)"

    # Get Modified Workspaces since last scan (Max 30 per hour)
    
    $workspacesModified = Invoke-PowerBIRestMethod -Url $modifiedRequestUrl -Method Get | ConvertFrom-Json

    if (!$workspacesModified -or $workspacesModified.Count -eq 0)
    {
        Write-Host "No workspaces modified"
    }
    else {
        Write-Host "Modified workspaces: $($workspacesModified.Count)"    

        $throttleErrorSleepSeconds = 3700
        $scanStatusSleepSeconds = 5
        $getInfoOuterBatchCount = 1500
        $getInfoInnerBatchCount = 100        

        Write-Host "Throttle Handling Variables: getInfoOuterBatchCount: $getInfoOuterBatchCount;  getInfoInnerBatchCount: $getInfoInnerBatchCount; throttleErrorSleepSeconds: $throttleErrorSleepSeconds"
        # postworkspaceinfo only allows 16 parallel requests, Get-ArrayInBatches allows to create a two level batch strategy. It should support initial load without throttling on tenants with ~50000 workspaces

        Get-ArrayInBatches -array $workspacesModified -label "GetInfo Global Batch" -batchCount $getInfoOuterBatchCount -script {
            param($workspacesModifiedOuterBatch)
                                            
            $script:workspacesScanRequests = @()

            # Call GetInfo in batches of 100 (MAX 500 requests per hour)
            Get-ArrayInBatches -array $workspacesModifiedOuterBatch -label "GetInfo Local Batch" -batchCount $getInfoInnerBatchCount -script {
                param($workspacesBatch)
                
                Wait-On429Error -tentatives 1 -sleepSeconds $throttleErrorSleepSeconds -script {
                    
                    $bodyStr = @{"workspaces" = @($workspacesBatch.Id) } | ConvertTo-Json
        
                    $getInfoDetails = "lineage=true&datasourceDetails=true&datasetSchema=true&datasetExpressions=true&getArtifactUsers=true"
        
                    # $script: scope to reference the outerscope variable

                    $getInfoResult = @(Invoke-PowerBIRestMethod -Url "admin/workspaces/getInfo?$getInfoDetails" -Body $bodyStr -method Post | ConvertFrom-Json)

                    $script:workspacesScanRequests += $getInfoResult

                }
            }                

            # Wait for Scan to execute - https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspaceinfo_getscanstatus (10,000 requests per hour)
        
            while(@($workspacesScanRequests |? status -in @("Running", "NotStarted")))
            {
                Write-Host "Waiting for scan results, sleeping for $scanStatusSleepSeconds seconds..."
        
                Start-Sleep -Seconds $scanStatusSleepSeconds
        
                foreach ($workspaceScanRequest in $workspacesScanRequests)
                {            
                    $scanStatus = Invoke-PowerBIRestMethod -Url "admin/workspaces/scanStatus/$($workspaceScanRequest.id)" -method Get | ConvertFrom-Json
        
                    Write-Host "Scan '$($scanStatus.id)' : '$($scanStatus.status)'"
        
                    $workspaceScanRequest.status = $scanStatus.status
                }
            }
        
            # Get Scan results (500 requests per hour) - https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspaceinfo_getscanresult    
        
            foreach ($workspaceScanRequest in $workspacesScanRequests)
            {   
                Wait-On429Error -tentatives 1 -sleepSeconds $throttleErrorSleepSeconds -script {

                    $scanResult = Invoke-PowerBIRestMethod -Url "admin/workspaces/scanResult/$($workspaceScanRequest.id)" -method Get | ConvertFrom-Json
            
                    Write-Host "Scan Result'$($scanStatus.id)' : '$($scanResult.workspaces.Count)'"
            
                    $outputFilePath = "$scansOutputPath\$($workspaceScanRequest.id).json"
            
                    $scanResult | Add-Member –MemberType NoteProperty –Name "scanCreatedDateTime"  –Value $workspaceScanRequest.createdDateTime -Force
            
                    ConvertTo-Json $scanResult -Depth 10 -Compress | Out-File $outputFilePath -force

                }
        
            }
        }                        
        
    }

    #endregion

    # Save to Blob

    if ($config.StorageAccountConnStr) {
        Write-Host "Writing to Blob Storage"
        
        $storageRootPath = "$($config.StorageAccountContainerRootPath)/catalog"

        @($scansOutputPath, $snapshotOutputPath) |% {
            Add-FolderToBlobStorage -storageAccountConnStr $config.StorageAccountConnStr -storageContainerName $config.StorageAccountContainerName -storageRootPath $storageRootPath -folderPath $_ -rootFolderPath $outputPath   
        }
    }

    # Save State

    New-Item -Path (Split-Path $stateFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $state.Catalog.LastRun = [datetime]::UtcNow.Date.ToString("o")

    ConvertTo-Json $state | Out-File $stateFilePath -force -Encoding utf8
}
finally
{
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}