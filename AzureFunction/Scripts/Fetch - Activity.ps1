#Requires -Modules MicrosoftPowerBIMgmt.Profile

param(
    [psobject]$config,
    [string]$stateFilePath
)

try {
    Write-Host "Starting Power BI Activity Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()

    if ($config.ActivityFileBatchSize) {
        $outputBatchCount = $config.ActivityFileBatchSize
    } else {
        $outputBatchCount = 5000
    }

    $rootOutputPath = "$($config.OutputPath)\activity"
    New-Item -ItemType Directory -Path $rootOutputPath -ErrorAction SilentlyContinue | Out-Null

    $outputPath = "$rootOutputPath\{0:yyyy}\{0:MM}"

    if (!$stateFilePath) {
        $stateFilePath = "$($config.OutputPath)\state.json"
    }

    if (Test-Path $stateFilePath) {
        $state = Get-Content $stateFilePath | ConvertFrom-Json
    } else {
        $state = New-Object psobject
    }

    $maxHistoryDate = [datetime]::UtcNow.Date.AddDays(-30)

    if ($state.Activity.LastRun) {
        if (!($state.Activity.LastRun -is [datetime])) {
            $state.Activity.LastRun = [datetime]::Parse($state.Activity.LastRun).ToUniversalTime()
        }
        $pivotDate = $state.Activity.LastRun
    } else {
        $state | Add-Member -NotePropertyName "Activity" -NotePropertyValue @{"LastRun" = $null } -Force
        $pivotDate = $maxHistoryDate
    }

    if ($pivotDate -lt $maxHistoryDate) {
        Write-Host "Last run was more than 30 days ago"
        $pivotDate = $maxHistoryDate
    }

    Write-Host "Since: $($pivotDate.ToString("s"))"
    Write-Host "OutputBatchCount: $outputBatchCount"

    Write-Host "Getting OAuth Token"

    if ($config.ServicePrincipal.AppId) {
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)
        $pbiAccount = Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential -Environment $config.ServicePrincipal.Environment
    } else {
        $pbiAccount = Connect-PowerBIServiceAccount
    }

    Write-Host "Login with: $($pbiAccount.UserName)"

    # Gets audit data for each day
    while ($pivotDate -le [datetime]::UtcNow) {
        Write-Host "Getting audit data for: '$($pivotDate.ToString("yyyyMMdd"))'"

        $activityAPIUrl = "admin/activityevents?startDateTime='$($pivotDate.ToString("s"))'&endDateTime='$($pivotDate.AddHours(24).AddSeconds(-1).ToString("s"))'"

        $audits = @()
        $pageIndex = 1
        $flagNoActivity = $true

        do {
            if (!$result.continuationUri) {
                $result = Invoke-PowerBIRestMethod -Url $activityAPIUrl -method Get | ConvertFrom-Json
            } else {
                $result = Invoke-PowerBIRestMethod -Url $result.continuationUri -method Get | ConvertFrom-Json
            }

            if ($result.activityEventEntities) {
                $audits += @($result.activityEventEntities)
            }

            if ($audits.Count -ne 0 -and ($audits.Count -ge $outputBatchCount -or $null -eq $result.continuationToken)) {
                if ($pageIndex -eq 1) {
                    $outputFilePath = ("$outputPath\{0:yyyyMMdd}.json" -f $pivotDate)
                } else {
                    $outputFilePath = ("$outputPath\{0:yyyyMMdd}_$pageIndex.json" -f $pivotDate)
                }

                Write-Host "Writing '$($audits.Count)' audits"

                New-Item -Path (Split-Path $outputFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

                ConvertTo-Json @($audits) -Compress -Depth 10 | Out-File $outputFilePath -force

                if ($config.StorageAccountName -and $config.StorageAccountContainerName) {
                    Write-Host "Writing to Blob Storage using RBAC authentication"

                    $storageRootPath = "$($config.StorageAccountContainerRootPath)/activity"

                    # Create Storage Context (Automatically Uses Managed Identity)
                    $ctx = New-AzStorageContext -StorageAccountName $config.StorageAccountName

                    # Upload file without authentication
                    Set-AzStorageBlobContent -File $outputFilePath -Container $config.StorageAccountContainerName -Blob ("activity/" + (Split-Path -Leaf $outputFilePath)) -Context $ctx -Force

                    Write-Host "Deleting local file '$outputFilePath'"
                    Remove-Item $outputFilePath -Force
                }

                $flagNoActivity = $false

                $pageIndex++
                $audits = @()
            }
        }
        while ($null -ne $result.continuationToken)

        if ($flagNoActivity) {
            Write-Warning "No audit logs for date: '$($pivotDate.ToString("yyyyMMdd"))'"
        }

        $state.Activity.LastRun = $pivotDate.Date.ToString("o")

        $pivotDate = $pivotDate.AddDays(1)

        # Save state
        Write-Host "Saving state"
        New-Item -Path (Split-Path $stateFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        ConvertTo-Json $state | Out-File $stateFilePath -force -Encoding utf8
    }

}
finally {
    $stopwatch.Stop()
    Write-Host "Elapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}
