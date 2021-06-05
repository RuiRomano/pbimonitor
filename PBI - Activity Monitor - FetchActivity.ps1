#Requires -Modules @{ ModuleName="PowerBIPS"; ModuleVersion="2.0.4.11" }

param(        
    $outputPath = ".\Data\Activity\{0:yyyy}\{0:MM}",   
    $configFilePath = ".\Config.json"
)

$VerbosePreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

Set-Location $currentPath

if (Test-Path $configFilePath)
{
    $config = Get-Content $configFilePath | ConvertFrom-Json
}
else
{
    throw "Cannot find config file '$configFilePath'"
}

Write-Host "Getting OAuth Token"

$authToken = Get-PBIAuthToken -clientId $config.ServicePrincipal.AppId -clientSecret $config.ServicePrincipal.AppSecret -tenantId $config.ServicePrincipal.TenantId

if ($config.Activity.LastRun)
{
    $pivotDate = [datetime]::Parse($config.Activity.LastRun).ToUniversalTime()
}
else
{
    $config | Add-Member -NotePropertyName "Activity" -NotePropertyValue @{"LastRun" = $null } -Force   

    $pivotDate = [datetime]::UtcNow.Date.AddDays(-30)
}


# Gets audit data daily

while($pivotDate -le [datetime]::UtcNow)
{           
    Write-Host "Getting audit data for: '$($pivotDate.ToString("yyyyMMdd"))'"

    $outputFilePath = ("$outputPath\{0:yyyyMMdd}.json" -f $pivotDate)

    $odataParams = "startDateTime='$($pivotDate.ToString("s"))'&endDateTime='$($pivotDate.AddHours(24).AddSeconds(-1).ToString("s"))'"
    
    $audits = @(Invoke-PBIRequest -authToken $authToken -resource "activityevents" -admin -odataParams $odataParams)

    if ($audits.Count -gt 0)
    {
        Write-Host "'$($audits.Count)' audits"

        New-Item -Path (Split-Path $outputFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

        ConvertTo-Json $audits -Compress -Depth 5 | Out-File $outputFilePath -force
    }
    else
    {
        Write-Warning "No audit logs for date: '$($pivotDate.ToString("yyyyMMdd"))'"
    }

    $config.Activity.LastRun = $pivotDate.Date.ToString("o")

    $pivotDate = $pivotDate.AddDays(1)

    # Save config 

    ConvertTo-Json $config | Out-File $configFilePath -force
}