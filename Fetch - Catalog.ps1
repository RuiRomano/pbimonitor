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

    $outputPath = "$($config.OutputPath)\Catalog"    
    
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

    # Get Modified Workspaces since last scan
    
    $workspacesModified = Invoke-PowerBIRestMethod -Url $modifiedRequestUrl -Method Get | ConvertFrom-Json

    if (!$workspacesModified)
    {
        Write-Host "No workspaces modified"
    }

    Write-Host "Modified workspaces: $($workspacesModified.Count)"    

    $skip = 0
    $batchCount = 100
    $workspacesScanRequests = @()

    # Call GetInfo to request workspace scan in batches of 100 (throtling after 500 calls per hour) https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspaceinfo_postworkspaceinfo
    do
    {   
        $workspacesBatch = @($workspacesModified | Select -First $batchCount -Skip $skip)

        if ($workspacesBatch)
        {
            Write-Host "Requesting workspace scan: $($skip + $batchCount) / $($workspacesModified.Count)"
    
            $bodyStr = @{"workspaces" = @($workspacesBatch.Id) } | ConvertTo-Json

            $getInfoDetails = "lineage=true&datasourceDetails=true&datasetSchema=true&datasetExpressions=true&getArtifactUsers=true"

            $workspacesScanRequests += (Invoke-PowerBIRestMethod -Url "admin/workspaces/getInfo?$getInfoDetails" -Body $bodyStr -method Post | ConvertFrom-Json)

            $skip += $batchCount            
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
            $scanStatus = Invoke-PowerBIRestMethod -Url "admin/workspaces/scanStatus/$($workspaceScanRequest.id)" -method Get | ConvertFrom-Json

            Write-Host "Scan '$($scanStatus.id)' : '$($scanStatus.status)'"

            $workspaceScanRequest.status = $scanStatus.status
        }
    }

    # Get Scan results (500 requests per hour) - https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspaceinfo_getscanresult    

    foreach ($workspaceScanRequest in $workspacesScanRequests)
    {   
        $scanResult = Invoke-PowerBIRestMethod -Url "admin/workspaces/scanResult/$($workspaceScanRequest.id)" -method Get | ConvertFrom-Json

        Write-Host "Scan Result'$($scanStatus.id)' : '$($scanResult.workspaces.Count)'"

        $outputFilePath = "$scansOutputPath\$($workspaceScanRequest.id).json"

        $scanResult | Add-Member –MemberType NoteProperty –Name "scanCreatedDateTime"  –Value $workspaceScanRequest.createdDateTime -Force

        ConvertTo-Json $scanResult -Depth 10 -Compress | Out-File $outputFilePath -force

    }

    #endregion

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