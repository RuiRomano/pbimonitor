#Requires -Modules MicrosoftPowerBIMgmt.Profile, MicrosoftPowerBIMgmt.Workspaces

## README - This script will run with the configured ServicePrincipal.
param(
    [psobject]$config,
    $workspaceFilter = @()
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"

# Function to Get Managed Identity OAuth Token for Azure Storage
function Add-FileToBlobStorage {
    param (
        [string]$storageAccountName,
        [string]$containerName,
        [string]$filePath,
        [string]$blobPath
    )

    Write-Host "Uploading file '$filePath' to Azure Blob Storage"

    # Create Storage Context (Automatically Uses Managed Identity)
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName

    # Upload File to Blob Storage (No Authentication Required)
    Set-AzStorageBlobContent -File $filePath -Container $containerName -Blob $blobPath -Context $ctx -Force

    Write-Host "✅ File successfully uploaded to Azure Blob Storage."
}

try {
    Write-Host "Starting Power BI Dataset Refresh History Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()

    # Ensure output folders exist
    $rootOutputPath = "$($config.OutputPath)\datasetrefresh"
    $outputPath = ("$rootOutputPath\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)
    $tempPath = Join-Path $outputPath "_temp"

    New-Item -ItemType Directory -Path $tempPath -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null

    Write-Host "Getting OAuth Token"

    if ($config.ServicePrincipal.AppId) {
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)

        $pbiAccount = Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential -Environment $config.ServicePrincipal.Environment
    }
    else {
        $pbiAccount = Connect-PowerBIServiceAccount
    }

    Write-Host "Login with: $($pbiAccount.UserName)"

    # Decode OAuth Token to Get User Identifier
    $token = (Get-PowerBIAccessToken -AsString).Split(" ")[1]
    $tokenPayload = $token.Split(".")[1].Replace('-', '+').Replace('_', '/')
    while ($tokenPayload.Length % 4) { $tokenPayload += "=" }
    $tokenPayload = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json
    $pbiUserIdentifier = $tokenPayload.oid

    # Get Workspaces + Users
    $workspacesFilePath = "$tempPath\workspaces.datasets.json"

    if (!(Test-Path $workspacesFilePath)) {
        $workspaces = Get-PowerBIWorkspace -Scope Organization -All -Include Datasets
        $workspaces | ConvertTo-Json -Depth 5 -Compress | Out-File $workspacesFilePath
    }
    else {
        Write-Host "Workspaces file already exists"
        $workspaces = Get-Content -Path $workspacesFilePath | ConvertFrom-Json
    }

    Write-Host "Workspaces: $($workspaces.Count)"

    # Filter Workspaces where User is a Member
    $workspaces = $workspaces | Where-Object { $_.users | Where-Object { $_.identifier -ieq $pbiUserIdentifier } }
    Write-Host "Workspaces where user is a member: $($workspaces.Count)"

    # Filter Only Active, V2 Workspaces with Datasets
    $workspaces = @($workspaces | Where-Object { $_.type -eq "Workspace" -and $_.state -eq "Active" -and $_.datasets.Count -gt 0 })

    if ($workspaceFilter -and $workspaceFilter.Count -gt 0) {
        $workspaces = @($workspaces | Where-Object { $workspaceFilter -contains $_.Id })
    }

    Write-Host "Workspaces to get refresh history: $($workspaces.Count)"

    $dsRefreshHistoryGlobal = @()
    $total = $Workspaces.Count
    $item = 0

    foreach ($workspace in $Workspaces) {
        $item++
        Write-Host "Processing workspace: '$($workspace.Name)' $item/$total"

        $refreshableDatasets = @($workspace.datasets | Where-Object { $_.isRefreshable -eq $true -and $_.addRowsAPIEnabled -eq $false })

        Write-Host "Refreshable Datasets: $($refreshableDatasets.Count)"

        foreach ($dataset in $refreshableDatasets) {
            try {
                Write-Host "Processing dataset: '$($dataset.name)'"

                $dsRefreshHistory = Invoke-PowerBIRestMethod -Url "groups/$($workspace.id)/datasets/$($dataset.id)/refreshes" -Method Get | ConvertFrom-Json
                $dsRefreshHistory = $dsRefreshHistory.value

                if ($dsRefreshHistory) {
                    $dsRefreshHistory = @($dsRefreshHistory | Select-Object *, @{Name = "dataSetId"; Expression = { $dataset.id } }, @{Name = "dataSet"; Expression = { $dataset.name } }`
                            , @{Name = "group"; Expression = { $workspace.name } }, @{Name = "configuredBy"; Expression = { $dataset.configuredBy } })

                    $dsRefreshHistoryGlobal += $dsRefreshHistory
                }
            }
            catch {
                $ex = $_.Exception
                Write-Error -message "Error processing dataset: '$($ex.Message)'" -ErrorAction Continue

                if ($ex.Message.Contains("Unauthorized") -or $ex.Message.Contains("(404) Not Found")) {
                    Write-Host "Got unauthorized/notfound, skipping workspace"
                    break
                }
            }
        }
    }

    if ($dsRefreshHistoryGlobal.Count -gt 0) {
        $outputFilePath = "$outputPath\workspaces.datasets.refreshes.json"

        ConvertTo-Json @($dsRefreshHistoryGlobal) -Compress -Depth 5 | Out-File $outputFilePath -force
        Write-Host "StorageAccountName: $($config.StorageAccountName)"
        Write-Host "StorageAccountContainerName: $($config.StorageAccountContainerName)"
        if ($config.StorageAccountName -and $config.StorageAccountContainerName) {
            Write-Host "Writing to Blob Storage using Managed Identity"

            $storageRootPath = "$($config.StorageAccountContainerRootPath)/datasetrefresh"

            Add-FileToBlobStorage -storageAccountName $config.StorageAccountName -containerName $config.StorageAccountContainerName -filePath $outputFilePath -blobPath ("datasetrefresh/" + (Split-Path -Leaf $outputFilePath))
        }
    }
}
finally {
    $stopwatch.Stop()
    Write-Host "Elapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}
