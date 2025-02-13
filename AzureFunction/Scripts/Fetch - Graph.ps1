param(
    [psobject]$config
)

#region Graph API Helper Functions

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

# Function to Get Azure AD Token for Graph API (Power BI)
function Get-AuthToken {
    [cmdletbinding()]
    param (
        [string]$authority = "https://login.microsoftonline.com",
        [string]$tenantid,
        [string]$appid,
        [string]$appsecret,
        [string]$resource
    )

    write-verbose "getting authentication token"

    $granttype = "client_credentials"
    $tokenuri = "$authority/$tenantid/oauth2/token?api-version=1.0"
    $appsecret = [System.Web.HttpUtility]::urlencode($appsecret)
    $body = "grant_type=$granttype&client_id=$appid&resource=$resource&client_secret=$appsecret"

    $token = Invoke-RestMethod -Method Post -Uri $tokenuri -Body $body

    return $token.access_token
}

# Function to Read Data from Microsoft Graph API (Power BI)
function Read-FromGraphAPI {
    [CmdletBinding()]
    param (
        [string]$url,
        [string]$accessToken,
        [string]$format = "JSON"
    )

    try {
        $headers = @{
            'Content-Type'  = "application/json"
            'Authorization' = "Bearer $accessToken"
        }

        $result = Invoke-RestMethod -Method Get -Uri $url -Headers $headers

        if ($format -eq "CSV") {
            ConvertFrom-CSV -InputObject $result | Write-Output
        }
        else {
            Write-Output $result.value

            while ($result.'@odata.nextLink') {
                $result = Invoke-RestMethod -Method Get -Uri $result.'@odata.nextLink' -Headers $headers
                Write-Output $result.value
            }
        }
    }
    catch [System.Net.WebException] {
        $ex = $_.Exception

        try {
            $statusCode = $ex.Response.StatusCode

            if ($statusCode -eq 429) {
                Write-Host "429 Throttling Error - Sleeping..."
                Start-Sleep -Seconds 1000
            }
            else {
                if ($null -ne $ex.Response) {
                    $statusCode = $ex.Response.StatusCode
                    $stream = $ex.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $errorContent = $reader.ReadToEnd()
                    $message = "$($ex.Message) - '$errorContent'"
                }
                else {
                    $message = "$($ex.Message) - 'Empty'"
                }
            }

            Write-Error -Exception $ex -Message $message
        }
        finally {
            if ($reader) { $reader.Dispose() }
            if ($stream) { $stream.Dispose() }
        }
    }
}

#endregion

try {
    Write-Host "Starting Graph API Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()

    Add-Type -AssemblyName System.Web

    $rootOutputPath = "$($config.OutputPath)\graph"
    $outputPath = ("$rootOutputPath\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)

    # Ensure the folder exists
    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null

    $graphUrl = "https://graph.microsoft.com/beta"
    $apiResource = "https://graph.microsoft.com"

    $graphCalls = @(
        @{ GraphUrl = "$graphUrl/users?`$select=id,displayName,assignedLicenses,UserPrincipalName"; FilePath = "$outputPath\users.json" },
        @{ GraphUrl = "$graphUrl/subscribedSkus?`$select=id,capabilityStatus,consumedUnits,prepaidUnits,skuid,skupartnumber,prepaidUnits"; FilePath = "$outputPath\subscribedskus.json" }
    )

    if ($config.GraphExtractGroups) {
        Write-Host "Adding graph call to extract groups"
        $graphCalls += @{ GraphUrl = "$graphUrl/groups?`$filter=securityEnabled eq true&`$select=id,displayName"; FilePath = "$outputPath\groups.json" }
    }

    $paginateCount = 10000

    if ($config.GraphPaginateCount) {
        $paginateCount = $config.GraphPaginateCount
    }

    Write-Host "GraphPaginateCount: $paginateCount"

    foreach ($graphCall in $graphCalls) {
        Write-Host "Getting OAuth token"
        $authToken = Get-AuthToken -resource $apiResource -appid $config.ServicePrincipal.AppId -appsecret $config.ServicePrincipal.AppSecret -tenantid $config.ServicePrincipal.TenantId

        Write-Host "Calling Graph API: '$($graphCall.GraphUrl)'"
        $data = Read-FromGraphAPI -accessToken $authToken -url $graphCall.GraphUrl | Select-Object * -ExcludeProperty "@odata.id"
        $filePath = $graphCall.FilePath

        Get-ArrayInBatches -array $data -label "Read-FromGraphAPI Local Batch" -batchCount $paginateCount -script {
            param($dataBatch, $i)

            if ($i) {
                $filePath = "$([System.IO.Path]::GetDirectoryName($filePath))\$([System.IO.Path]::GetFileNameWithoutExtension($filePath))_$i$([System.IO.Path]::GetExtension($filePath))"
            }

            Write-Host "Writing to file: '$filePath'"
            ConvertTo-Json @($dataBatch) -Compress -Depth 5 | Out-File $filePath -Force

            if ($config.StorageAccountName -and $config.StorageAccountContainerName) {
                Write-Host "Writing to Blob Storage using Managed Identity"
                Add-FileToBlobStorage -storageAccountName $config.StorageAccountName -containerName $config.StorageAccountContainerName -filePath $filePath -blobPath ("graph/" + (Split-Path -Leaf $filePath))
            }
        }
    }
}
finally {
    $stopwatch.Stop()
    Write-Host "Elapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}
