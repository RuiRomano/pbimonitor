#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt.Profile"; ModuleVersion="1.2.1026" }
#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt.Workspaces"; ModuleVersion="1.2.1026" }

param(        
    $configFilePath = ".\Config-Test.json",
    # ITs not the ServicePrincipal client id, its the Azure AD Object ID  - https://cloudsight.zendesk.com/hc/en-us/articles/360016785598-Azure-finding-your-service-principal-object-ID
    $servicePrincipalObjectId = $null,        
    $workspaceFilter = @() # @("28544d33-de5f-49cf-8e45-a2a8784fe31f", "d0641e3b-a0c6-404b-a422-afe7be6b2a4f")
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"

try
{
    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()

    $currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

    Set-Location $currentPath
    
    # Discover the Service Principal on Config Azure AD Object Id

    if (!$servicePrincipalObjectId)
    {
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

        # Find Token Object Id, by decoding OAUTH TOken - https://blog.kloud.com.au/2019/07/31/jwtdetails-powershell-module-for-decoding-jwt-access-tokens-with-readable-token-expiry-time/
        
        $token = (Get-PowerBIAccessToken -AsString).Split(" ")[1]
        $tokenPayload = $token.Split(".")[1].Replace('-', '+').Replace('_', '/')
        while ($tokenPayload.Length % 4) { $tokenPayload += "=" }
        $tokenPayload = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json
        $servicePrincipalObjectId = $tokenPayload.oid

        Disconnect-PowerBIServiceAccount
    }

    # Get token with admin account

    Connect-PowerBIServiceAccount

    # Get all tenant workspaces    

    $workspaces = Get-PowerBIWorkspace -Scope Organization -All

    Write-Host "Workspaces: $($workspaces.Count)"
     
    # Only look at active workspaces and V2

    $workspaces = @($workspaces | Where-Object {$_.type -eq "Workspace" -and $_.state -eq "Active"})

    if ($workspaceFilter -and $workspaceFilter.Count -gt 0)
    {
        $workspaces = @($workspaces | Where-Object { $workspaceFilter -contains $_.Id})
    }

    # Filter workspaces where the serviceprincipal is not there

    $workspaces = $workspaces | Where-Object {
        
        $members = @($_.users | Where-Object { $_.identifier -eq $servicePrincipalObjectId })
       
        if ($members.Count -eq 0)
        {
            $true
        }
        else
        {
            $false
        }
    }    

    Write-Host "Workspaces to set security: $($workspaces.Count)"    

    foreach($workspace in $workspaces)
    {  
        Write-Host "Adding service principal to workspace: $($workspace.name) ($($workspace.id))"

        $body = @{
            "identifier" = $servicePrincipalObjectId
            ;
            "groupUserAccessRight" = "Member"
            ;
            "principalType" = "App"
        }

        $bodyStr = ($body | ConvertTo-Json)
        
        Invoke-PowerBIRestMethod -method Post -url "admin/groups/$($workspace.id)/users" -body $bodyStr
    }

}
finally
{
    $stopwatch.Stop()

    Write-Host "Elapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}
