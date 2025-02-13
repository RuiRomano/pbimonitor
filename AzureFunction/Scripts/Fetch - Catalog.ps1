#Requires -Modules MicrosoftPowerBIMgmt.Profile

param(
    [psobject]$config,
    [bool]$reset = $false,
    [string]$stateFilePath
)

try {
    Write-Host "Starting Power BI Catalog Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()

    $outputPath = "$($config.OutputPath)\catalog"

    if (!$stateFilePath) {
        $stateFilePath = "$($config.OutputPath)\state.json"
    }

    if (Test-Path $stateFilePath) {
        $state = Get-Content $stateFilePath | ConvertFrom-Json

        # Ensure mandatory fields
        $state | Add-Member -NotePropertyName "Catalog" -NotePropertyValue (new-object PSObject) -ErrorAction SilentlyContinue
        $state.Catalog | Add-Member -NotePropertyName "LastRun" -NotePropertyValue $null -ErrorAction SilentlyContinue
        $state.Catalog | Add-Member -NotePropertyName "LastFullScan" -NotePropertyValue $null -ErrorAction SilentlyContinue
    }
    else {
        $state = New-Object psobject
        $state | Add-Member -NotePropertyName "Catalog" -NotePropertyValue @{"LastRun" = $null; "LastFullScan" = $null } -Force
    }

    $state.Catalog.LastRun = [datetime]::UtcNow.Date.ToString("o")

    # Ensure folders
    $scansOutputPath = Join-Path $outputPath ("scans\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)
    $snapshotOutputPath = Join-Path $outputPath ("snapshots\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)

    New-Item -ItemType Directory -Path $scansOutputPath -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $snapshotOutputPath -ErrorAction SilentlyContinue | Out-Null

    Write-Host "Getting OAuth Token"

    if ($config.ServicePrincipal.AppId) {
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)
        $pbiAccount = Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential -Environment $config.ServicePrincipal.Environment
    }
    else {
        $pbiAccount = Connect-PowerBIServiceAccount
    }

    Write-Host "Login with: $($pbiAccount.UserName)"

    #region ADMIN API
    $snapshotFiles = @()

    $filePath = "$snapshotOutputPath\apps.json"
    $snapshotFiles += $filePath

    if (!(Test-Path $filePath)) {
        Write-Host "Getting Power BI Apps List"

        $result = Invoke-PowerBIRestMethod -Url "admin/apps?`$top=5000&`$skip=0 " -Method Get | ConvertFrom-Json
        $result = @($result.value)

        if ($result.Count -ne 0) {
            ConvertTo-Json $result -Depth 10 -Compress | Out-File $filePath -force
        }
        else {
            Write-Host "Tenant without PowerBI apps"
        }
    }
    else {
        Write-Host "'$filePath' already exists"
    }

    # Save to Blob
    if ($config.StorageAccountName -and $config.StorageAccountContainerName) {
        Write-Host "Writing Snapshots to Blob Storage using RBAC"

        $storageRootPath = "$($config.StorageAccountContainerRootPath)/catalog"
        $ctx = New-AzStorageContext -StorageAccountName $config.StorageAccountName

        foreach ($outputFilePath in $snapshotFiles) {
            if (Test-Path $outputFilePath) {
                Set-AzStorageBlobContent -File $outputFilePath -Container $config.StorageAccountContainerName -Blob ("catalog/" + (Split-Path -Leaf $outputFilePath)) -Context $ctx -Force

                Remove-Item $outputFilePath -Force
            }
            else {
                Write-Warning "Cannot find file '$outputFilePath'"
            }
        }
    }

    #endregion

    # Save State
    Write-Host "Saving state"

    New-Item -Path (Split-Path $stateFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $state.Catalog.LastRun = [datetime]::UtcNow.Date.ToString("o")

    if ($fullScan) {
        $state.Catalog.LastFullScan = [datetime]::UtcNow.Date.ToString("o")
    }

    ConvertTo-Json $state | Out-File $stateFilePath -force -Encoding utf8
}
finally {
    $stopwatch.Stop()
    Write-Host "Elapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}
