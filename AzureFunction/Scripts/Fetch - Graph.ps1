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

    $rootOutputPath = "$($config.OutputPath)\graph"
    
    $outputPath = ("$rootOutputPath\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today)

    # ensure folder

    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null

    $graphUrl = "https://graph.microsoft.com/beta"
    $apiResource = "https://graph.microsoft.com"

    $graphCalls = @(
        @{
            GraphUrl = "$graphUrl/users?`$select=id,displayName,assignedLicenses,UserPrincipalName";
            FilePath = "$outputPath\users.json"
        }
        ,
        @{
            GraphUrl = "$graphUrl/subscribedSkus?`$select=id,capabilityStatus,consumedUnits,prepaidUnits,skuid,skupartnumber,prepaidUnits";
            FilePath = "$outputPath\subscribedskus.json"
        }    
    )

    if ($config.GraphExtractGroups)
    {
        Write-Host "Adding graph call to extract groups"
        $graphCalls += @{
            #GraphUrl = "$graphUrl/groups?`$expand=members(`$select=id,displayName,appId,userPrincipalName)&`$select=id,displayName";
            GraphUrl = "$graphUrl/groups?`$filter=securityEnabled eq true&`$select=id,displayName";
            FilePath = "$outputPath\groups.json"
        }
    }

    $paginateCount = 10000  

    if ($config.GraphPaginateCount)
    {
        $paginateCount = $config.GraphPaginateCount
    }

    Write-Host "GraphPaginateCount: $paginateCount"   

    foreach ($graphCall in $graphCalls)
    {
        Write-Host "Getting OAuth token"

        $authToken = Get-AuthToken -resource $apiResource -appid $config.ServicePrincipal.AppId -appsecret $config.ServicePrincipal.AppSecret -tenantid $config.ServicePrincipal.TenantId

        Write-Host "Calling Graph API: '$($graphCall.GraphUrl)'"

        $data = Read-FromGraphAPI -accessToken $authToken -url $graphCall.GraphUrl | select * -ExcludeProperty "@odata.id"

        $filePath = $graphCall.FilePath

        Get-ArrayInBatches -array $data -label "Read-FromGraphAPI Local Batch" -batchCount $paginateCount -script {
            param($dataBatch, $i)
            
            if ($i)
            {
                $filePath = "$([System.IO.Path]::GetDirectoryName($filePath))\$([System.IO.Path]::GetFileNameWithoutExtension($filePath))_$i$([System.IO.Path]::GetExtension($filePath))"
            }

            if ($graphCall.GraphUrl -like "$graphUrl/groups*")
            {
                #$groupsWithMoreThan20Members = $dataBatch |? { $_.members.Count -ge 20 }
            
                #Write-Host "Groups with more than 20 members: $($groupsWithMoreThan20Members.Count)"
                
                #foreach($group in $groupsWithMoreThan20Members)

                Write-Host "Looping group batch to get members"

                foreach($group in $dataBatch)
                {        
                    $groupMembers = @(Read-FromGraphAPI -accessToken $authToken -url "$graphUrl/groups/$($group.id)/transitiveMembers?`$select=id,displayName,appId,userPrincipalName")
        
                    #$group.members = $groupMembers    
                    $group | Add-Member -NotePropertyName "members" -NotePropertyValue $groupMembers -ErrorAction SilentlyContinue   
                }
            }

            Write-Host "Writing to file: '$filePath'"

            ConvertTo-Json @($dataBatch) -Compress -Depth 5 | Out-File $filePath -Force
    
            if ($config.StorageAccountConnStr) {
    
                Write-Host "Writing to Blob Storage"
            
                $storageRootPath = "$($config.StorageAccountContainerRootPath)/graph"
        
                $outputFilePath = $filePath
         
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
    }

}
finally {
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}