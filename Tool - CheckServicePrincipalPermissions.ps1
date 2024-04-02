#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt.Profile"; ModuleVersion="1.2.1026" }

param(        
    $configFilePath = ".\Config-RRMSFT.json"
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"

try
{
    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()

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

    Write-Host "Getting OAuth Token for ServicePrincipal to find the ObjectId"

    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)
        
    Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential -Environment $config.ServicePrincipal.Environment

    $result = Invoke-PowerBIRestMethod -Url "admin/apps?`$top=10&`$skip=0 " -Method Get | ConvertFrom-Json         

    Write-Host "Apps Returned: $($result.value.Count)"

}
finally
{
    $stopwatch.Stop()

    Write-Host "Elapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}
