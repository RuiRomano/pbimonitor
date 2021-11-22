#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt.Profile"; ModuleVersion="1.2.1026" }

param(               
    [psobject]$config
    ,
    [string]$stateFilePath    
)

try {
    Write-Host "Starting Power BI Activity Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()   

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

    Write-Host "Getting OAuth Token"

    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)

    $pbiAccount = Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential -Environment $config.ServicePrincipal.Environment

    Write-Host "Login with: $($pbiAccount.UserName)"

    # Gets audit data for each day

    while ($pivotDate -le [datetime]::UtcNow) {           
        Write-Host "Getting audit data for: '$($pivotDate.ToString("yyyyMMdd"))'"

        $outputFilePath = ("$outputPath\{0:yyyyMMdd}.json" -f $pivotDate)
            
        $activityAPIUrl = "admin/activityevents?startDateTime='$($pivotDate.ToString("s"))'&endDateTime='$($pivotDate.AddHours(24).AddSeconds(-1).ToString("s"))'"

        # Get-PowerBIActivityEvent was having memory issues on large tenants

        $result = Invoke-PowerBIRestMethod -Url $activityAPIUrl -method Get | ConvertFrom-Json

        $audits = @($result.activityEventEntities)
                  
        while($result.continuationToken -ne $null)
        {          
            $result = Invoke-PowerBIRestMethod -Url $result.continuationUri -method Get | ConvertFrom-Json
                                
            if ($result.activityEventEntities)
            {
                $audits += @($result.activityEventEntities)
            }
        }

        if (!($audits -is [array])) {
             $audits = @($audits)
        }

        if ($audits.Count -gt 0) {
            Write-Host "'$($audits.Count)' audits"

            New-Item -Path (Split-Path $outputFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

            ConvertTo-Json @($audits) -Compress -Depth 5 | Out-File $outputFilePath -force
        }
        else {
            Write-Warning "No audit logs for date: '$($pivotDate.ToString("yyyyMMdd"))'"
        }

        $state.Activity.LastRun = $pivotDate.Date.ToString("o")

        $pivotDate = $pivotDate.AddDays(1)

        if ($config.StorageAccountConnStr -and (Test-Path $outputFilePath)) {
            Write-Host "Writing to Blob Storage"
            
            $storageRootPath = "$($config.StorageAccountContainerRootPath)/activity"

            Add-FileToBlobStorage -storageAccountConnStr $config.StorageAccountConnStr -storageContainerName $config.StorageAccountContainerName -storageRootPath $storageRootPath -filePath $outputFilePath -rootFolderPath $rootOutputPath         
        }

        # Save state 

        New-Item -Path (Split-Path $stateFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        
        ConvertTo-Json $state | Out-File $stateFilePath -force -Encoding utf8
        
    }

}
finally {
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}