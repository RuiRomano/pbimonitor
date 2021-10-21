#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt.Profile"; ModuleVersion="1.2.1026" }
#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt.Admin"; ModuleVersion="1.2.1026" }

param(               
    [psobject]$config    
)

try {
    Write-Host "Starting Power BI Activity Fetch"

    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()   

    $outputPath = "$($config.OutputPath)\Activity\{0:yyyy}\{0:MM}"    
    $stateFilePath = "$($config.OutputPath)\state.json"

    if (Test-Path $stateFilePath) {
        $state = Get-Content $stateFilePath | ConvertFrom-Json
    }
    else {
        $state = New-Object psobject 
    }

    if ($state.Activity.LastRun) {
        if (!($state.Activity.LastRun -is [datetime]))
        {
            $state.Activity.LastRun = [datetime]::Parse($state.Activity.LastRun).ToUniversalTime()
        }
        $pivotDate = $state.Activity.LastRun
    }
    else {
        $state | Add-Member -NotePropertyName "Activity" -NotePropertyValue @{"LastRun" = $null} -Force
        $pivotDate = [datetime]::UtcNow.Date.AddDays(-30)
    }

    Write-Host "Since: $($state.Activity.LastRun)"

    Write-Host "Getting OAuth Token"

    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)

    Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential -Environment $config.ServicePrincipal.Environment

    # Gets audit data for each day

    while ($pivotDate -le [datetime]::UtcNow) {           
        Write-Host "Getting audit data for: '$($pivotDate.ToString("yyyyMMdd"))'"

        $outputFilePath = ("$outputPath\{0:yyyyMMdd}.json" -f $pivotDate)

        $audits = Get-PowerBIActivityEvent -StartDateTime $pivotDate.ToString("s") -EndDateTime $pivotDate.AddHours(24).AddSeconds(-1).ToString("s") | ConvertFrom-Json

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

        # Save state 

        ConvertTo-Json $state | Out-File $stateFilePath -force -Encoding utf8
    }

}
catch {
    $ex = $_.Exception

    if ($ex.ToString().Contains("429 (Too Many Requests)")) {
        Write-Host "429 Throthling Error - Need to wait before making another request..." -ForegroundColor Yellow
    }  

    Resolve-PowerBIError -Last

    throw
}
finally {
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}