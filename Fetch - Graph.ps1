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

    $tokenuri = "$authority/$tenantid/oauth2/token?api-version=1.0"

    $appsecret = [System.Web.HttpUtility]::urlencode($appsecret)

    $body = "grant_type=$granttype&client_id=$appid&resource=$resource&client_secret=$appsecret"    

    $token = invoke-restmethod -method post -uri $tokenuri -body $body

    $accesstoken = $token.access_token    

    write-output $accesstoken

}

function Read-FromGraphAPI {
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
    Write-Host "Starting Graph API Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()   

    Add-Type -AssemblyName System.Web

    $outputPath = ("$($config.OutputPath)\Graph\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)

    # ensure folder

    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null

    # Get the authentication token

    Write-Host "Getting OAuth token"

    $authToken = Get-AuthToken -resource "https://graph.microsoft.com" -appid $config.ServicePrincipal.AppId -appsecret $config.ServicePrincipal.AppSecret -tenantid $config.ServicePrincipal.TenantId

    $graphUrl = "https://graph.microsoft.com/beta"

    # Get Users & Assigned Licenses

    Write-Host "Getting Users from Graph"

    $users = Read-FromGraphAPI -accessToken $authToken -url "$graphUrl/users?`$select=id,mail,companyName,displayName,assignedLicenses,onPremisesUserPrincipalName,UserPrincipalName,jobTitle,userType" | select * -ExcludeProperty "@odata.id"

    $filePath = "$outputPath\users.json"

    ConvertTo-Json @($users) -Compress -Depth 5 | Out-File $filePath -Force 

    # Get Skus & license count

    Write-Host "Getting SKUs from Graph"

    $skus = Read-FromGraphAPI -accessToken $authToken -url "$graphUrl/subscribedSkus?`$select=id,capabilityStatus,consumedUnits, prepaidUnits,skuid,skupartnumber,prepaidUnits" | select * -ExcludeProperty "@odata.id"    

    $filePath = "$outputPath\subscribedSkus.json"
    
    ConvertTo-Json @($skus) -Compress -Depth 5 | Out-File $filePath -Force

    # Save to Blob

    if ($config.StorageAccountConnStr) {
        Write-Host "Writing to Blob Storage"
    
        $storageRootPath = "$($config.StorageAccountContainerRootPath)/graph"

        Add-FolderToBlobStorage -storageAccountConnStr $config.StorageAccountConnStr -storageContainerName $config.StorageAccountContainerName -storageRootPath $storageRootPath -folderPath "$($config.OutputPath)\Graph" 
    }

    <#
    Write-Host "Get AD Groups"

    $groups = Read-FromGraphAPI -accessToken $authToken -url "$graphUrl/groups?`$expand=members&`$select=id,description,displayName,createdDateTime,deletedDateTime,groupTypes"

    $groups = $groups | select * -ExcludeProperty "@odata.id"    

    $filePath = "$outputPath\groups.json"

    $groups | ConvertTo-Json -Compress -Depth 5 | Out-File $filePath -Force

    $groupsWithMoreThan20Members = $groups |? { $_.members.Count -eq 20 }

    $groupsMembers = @()

    Write-Host "Get Group Members from $($groupsWithMoreThan20Members.Count) groups"

    foreach($group in $groupsWithMoreThan20Members)
    {        
        $groupMembers = Read-FromGraphAPI -accessToken $authToken -url "$graphUrl/groups/$($group.id)/members?`$select=id" | Select id,  @{n='groupId';e={$group.id}}

        $groupsMembers += $groupMembers
    
    }
    
    $filePath = "$outputPath\groupsmembers.json"

    ConvertTo-Json @($groupsMembers) -Compress -Depth 5 | Out-File $filePath -Force
#>

}
finally {
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}