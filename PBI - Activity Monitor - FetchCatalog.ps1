#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

param(        
    $outputPath = ".\Data\Catalog",    
    $configFilePath = ".\Config.json",
    $reset = $false
)

try
{
    Write-Host "Starting Power BI Activity Monitor Catalog Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()   

    $currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

    Set-Location $currentPath

    # ensure folder
 
    $scansOutputPath = Join-Path $outputPath ("scans\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)
    $snapshotOutputPath = Join-Path $outputPath ("snapshots\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)

    New-Item -ItemType Directory -Path $scansOutputPath -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $snapshotOutputPath -ErrorAction SilentlyContinue | Out-Null

    
    if (Test-Path $configFilePath)
    {
        $config = Get-Content $configFilePath | ConvertFrom-Json
    }
    else
    {
        throw "Cannot find config file '$configFilePath'"
    }


    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)

    Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential

    #region ADMIN API    

    $filePath = "$snapshotOutputPath\apps.json"    

    if (!(Test-Path $filePath))
    {     
        $result = Invoke-PowerBIRestMethod -Url "admin/apps?`$top=5000&`$skip=0 " -Method Get | ConvertFrom-Json

        @($result.value) | ConvertTo-Json -Depth 5 -Compress | Out-File $filePath
    }
    else
    {
        Write-Host "'$filePath' already exists"
    }

    #endregion

    #region Workspace Scans: 1 - Get Modified; 2 - Start Scan for modified; 3 - Wait for scan finish; 4 - Get Results

    Write-Host "Getting workspaces to scan"

    $modifiedRequestUrl = "admin/workspaces/modified"

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
    
    $workspacesModified = Invoke-PowerBIRestMethod -Url $modifiedRequestUrl -Method Get | ConvertFrom-Json

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

    ConvertTo-Json $config | Out-File $configFilePath -force

    #endregion

}
catch
{
    $ex = $_.Exception

    if ($ex.ToString().Contains("429 (Too Many Requests)"))
    {
        Write-Host "429 Throthling Error - Need to wait before making another request..." -ForegroundColor Yellow
    }  

    Write-Host $ex.ToString() -ForegroundColor Red

    throw
}
finally
{
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}