param(        
    [psobject]$config    
)

#region Graph API Helper Functions

function Get-AuthToken {
    [cmdletbinding()]
    param
    (
        [string]
        $authority = "https://login.microsoftonline.com",
        [string]
        $tenantid,
        [string]
        $appid,
        [string]
        $appsecret ,
        [string]
        $resource         
    )

    write-verbose "getting authentication token"
    
    $granttype = "client_credentials"    

    $tokenuri = "https://login.microsoftonline.com/$($tenantId)/oauth2/token"

    #$appsecret = [System.Web.HttpUtility]::urlencode($appsecret)

    $body = @{
    grant_type    = "client_credentials"
    client_id     = $appid
    client_secret = $appsecret
    resource      = $resource
    }    


    $token = invoke-restmethod -uri $tokenuri -method Post -ContentType "application/x-www-form-urlencoded" -body $body

    $accesstoken = $token.access_token    

    write-output $accesstoken

}

function Read-FromTenantAPI {
    [CmdletBinding()]
    param
    (
        [string]
        $url,
        [string]
        $accessToken,
        [string]
        $format = "JSON"     
    )

    #https://blogs.msdn.microsoft.com/exchangedev/2017/04/07/throttling-coming-to-outlook-api-and-microsoft-graph/

    try {
        $headers = @{
            'Content-Type'  = "application/json"
            'Authorization' = "Bearer $accessToken"
        }    

        $result = Invoke-RestMethod -Method Get -Uri $url -Headers $headers


        Write-Output $result           

        }

    catch [System.Net.WebException] {
        $ex = $_.Exception

        try {                
            $statusCode = $ex.Response.StatusCode

            if ($statusCode -eq 429) {              
                $message = "429 Throthling Error - Sleeping..."

                Write-Host $message

                Start-Sleep -Seconds 1000
            }              
            else {
                if ($ex.Response -ne $null) {
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
    Write-Host "Starting Tenant API Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()   

    Add-Type -AssemblyName System.Web

    $rootOutputPath = "$($config.OutputPath)\tenant"
    
    $outputPath = ("$rootOutputPath\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)

    # ensure folder

    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null

    $tenantUrl = "https://api.fabric.microsoft.com/v1/admin/tenantsettings"
    $apiResource = "https://api.fabric.microsoft.com/"
    $TenantFilePath = "$($outputPath)\tenant-settings.json"



        Write-Host "Getting OAuth token"

        $authToken = Get-AuthToken -resource $apiResource -appid $config.ServicePrincipal.AppId -appsecret $config.ServicePrincipal.AppSecret -tenantid $config.ServicePrincipal.TenantId

        Write-Host "Calling Graph API: https://api.fabric.microsoft.com/v1/admin/tenantsettings"

        $data = Read-FromTenantAPI -accessToken $authToken -url $tenantUrl

        Write-Host "Writing to file: '$($TenantFilePath)'"

        ConvertTo-Json $data -Compress -Depth 5 | Out-File $TenantFilePath -Force

        if ($config.StorageAccountConnStr) {

            Write-Host "Writing to Blob Storage"
        
            $storageRootPath = "$($config.StorageAccountContainerRootPath)/tenant"
    
            $outputFilePath = $TenantFilePath
     
            if (Test-Path $outputFilePath)
            {
                Add-FileToBlobStorage -storageAccountConnStr $config.StorageAccountConnStr -storageContainerName $config.StorageAccountContainerName -storageRootPath $storageRootPath -filePath $outputFilePath -rootFolderPath $rootOutputPath    

                Remove-Item $outputFilePath -Force
            }
            else {
                Write-Host "Cannot find file '$outputFilePath'"
            }
        }
    

}
finally {
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}