#Requires -Modules MicrosoftPowerBIMgmt.Profile

param(               
    [psobject]$config
    ,
    [string]$stateFilePath     
)

try {
    Write-Host "Starting Power BI Activity Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()   

    if ($config.ActivityFileBatchSize)
    {
        $outputBatchCount = $config.ActivityFileBatchSize
    }
    else {
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
    }
    else {
        $state = New-Object psobject 
    }
    
    if ($state.Activity.LastRun) {
        if (!($state.Activity.LastRun -is [datetime])) {
            $state.Activity.LastRun = [datetime]::Parse($state.Activity.LastRun).ToUniversalTime()
        }
        $pivotDate = $state.Activity.LastRun
    }
    else {
        $state | Add-Member -NotePropertyName "Activity" -NotePropertyValue @{"LastRun" = $null } -Force
        $pivotDate = [datetime]::UtcNow.Date.AddDays(-30)
    }

    Write-Host "Since: $($state.Activity.LastRun)"
    Write-Host "OutputBatchCount: $outputBatchCount"

    Write-Host "Getting OAuth Token"

    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)

    $pbiAccount = Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential -Environment $config.ServicePrincipal.Environment

    Write-Host "Login with: $($pbiAccount.UserName)"
    
    # Gets audit data for each day

    while ($pivotDate -le [datetime]::UtcNow) {           
        Write-Host "Getting audit data for: '$($pivotDate.ToString("yyyyMMdd"))'"        
            
        $activityAPIUrl = "admin/activityevents?startDateTime='$($pivotDate.ToString("s"))'&endDateTime='$($pivotDate.AddHours(24).AddSeconds(-1).ToString("s"))'"

        $audits = @()                  
        $pageIndex = 1
        $flagNoActivity = $true

        do
        {          
            if (!$result.continuationUri)
            {
                $result = Invoke-PowerBIRestMethod -Url $activityAPIUrl -method Get | ConvertFrom-Json
            }
            else {
                $result = Invoke-PowerBIRestMethod -Url $result.continuationUri -method Get | ConvertFrom-Json
            }            
                                
            if ($result.activityEventEntities)
            {
                $audits += @($result.activityEventEntities)               
            }

            if ($audits.Count -ne 0 -and ($audits.Count -ge $outputBatchCount -or $result.continuationToken -eq $null))
            {
                # To avoid duplicate data on existing files, first dont append pageindex to overwrite existing full file

                if ($pageIndex -eq 1)
                {
                    $outputFilePath = ("$outputPath\{0:yyyyMMdd}.json" -f $pivotDate)                        
                }
                else {
                    $outputFilePath = ("$outputPath\{0:yyyyMMdd}_$pageIndex.json" -f $pivotDate)
                }                    

                Write-Host "Writing '$($audits.Count)' audits"

                New-Item -Path (Split-Path $outputFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    
                ConvertTo-Json @($audits) -Compress -Depth 5 | Out-File $outputFilePath -force

                if ($config.StorageAccountConnStr -and (Test-Path $outputFilePath)) {
                    Write-Host "Writing to Blob Storage"
                    
                    $storageRootPath = "$($config.StorageAccountContainerRootPath)/activity"
        
                    Add-FileToBlobStorage -storageAccountConnStr $config.StorageAccountConnStr -storageContainerName $config.StorageAccountContainerName -storageRootPath $storageRootPath -filePath $outputFilePath -rootFolderPath $rootOutputPath         

                    Write-Host "Deleting local file '$outputFilePath'"

                    Remove-Item $outputFilePath -Force
                }
                
                $flagNoActivity = $false

                $pageIndex++

                $audits = @()
            }
        }
        while($result.continuationToken -ne $null)

        if ($flagNoActivity)
        {
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

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}