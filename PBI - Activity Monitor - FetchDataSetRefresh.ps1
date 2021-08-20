#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

param(          
    $outputPath = (".\Data\DataRefresh\{0:yyyy}\{0:MM}\{0:dd}" -f [datetime]::Today),
    $configFilePath = ".\Config.json",    
    $workspaceFilter = @()
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"

try
{
    $stopwatch = [System.Diagnostics.Stopwatch]::new()
    $stopwatch.Start()


    $currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

    Set-Location $currentPath

    # ensure folder

    $tempPath = Join-Path $outputPath "_temp"

    New-Item -ItemType Directory -Path $tempPath -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $outputPath -ErrorAction SilentlyContinue | Out-Null
    
    if (Test-Path $configFilePath)
    {
        $config = Get-Content $configFilePath | ConvertFrom-Json
    }
    else
    {
        throw "Cannot find config file '$configFilePath'"
    }

    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $config.ServicePrincipal.AppId, ($config.ServicePrincipal.AppSecret | ConvertTo-SecureString -AsPlainText -Force)

    Connect-PowerBIServiceAccount -ServicePrincipal -Tenant $config.ServicePrincipal.TenantId -Credential $credential

    #region Workspace Users

    # Get workspaces + users (need this because users dont come in the async api)

    $workspacesFilePath = "$tempPath\workspaces.datasets.json"    

    if (!(Test-Path $workspacesFilePath))
    {
        # TODO - Limited to 5000 workspaces, if more need to loop using $top & $skip

        $workspaces = Invoke-PowerBIRestMethod -Url "admin/groups?`$expand=users,datasets&`$top=5000" -Method Get | ConvertFrom-Json      

        $workspaces = $workspaces.value        

        $workspaces | ConvertTo-Json -Depth 5 -Compress | Out-File $workspacesFilePath        
    }
    else
    {
        Write-Host "Workspaces file already exists"

        $workspaces = Get-Content -Path $workspacesFilePath | ConvertFrom-Json
    }    

    Write-Host "Workspaces: $($workspaces.Count)"

    if ($config.ServicePrincipal.AppObjectId)
    {
        $workspaces = $workspaces |? { $_.users |? { $_.identifier -ieq $config.ServicePrincipal.AppObjectId } }

        Write-Host "Workspaces with granted permission: $($workspaces.Count)"
    }
    # Only look at Active, V2 Workspaces and with Datasets

    $workspaces = @($workspaces |? {$_.type -eq "Workspace" -and $_.state -eq "Active" -and $_.datasets.Count -gt 0})

    if ($workspaceFilter -and $workspaceFilter.Count -gt 0)
    {
        $workspaces = @($workspaces |? { $workspaceFilter -contains $_.Id})
    }

    Write-Host "Workspaces to get refresh history: $($workspaces.Count)"
   
    $total = $Workspaces.Count
    $item = 0
        
    foreach($workspace in $Workspaces)
    {          
        $item++
                   
        Write-Host "Processing workspace: '$($workspace.Name)' $item/$total" 

        Write-Host "Datasets: $($workspace.datasets.Count)"

        $refreshableDatasets = @($workspace.datasets |? { $_.isRefreshable -eq $true -and $_.addRowsAPIEnabled -eq $false})

        Write-Host "Refreshable Datasets: $($refreshableDatasets.Count)"

        foreach($dataset in $refreshableDatasets)
        {
            try
            {
                Write-Host "Processing dataset: '$($dataset.name)'" 

                Write-Host "Getting refresh history"

                $dsRefreshHistory = Invoke-PowerBIRestMethod -Url "groups/$($workspace.id)/datasets/$($dataset.id)/refreshes" -Method Get | ConvertFrom-Json

                $dsRefreshHistory = $dsRefreshHistory.value

                if ($dsRefreshHistory)
                {
                    $dsRefreshHistory = $dsRefreshHistory | Select *, @{Name="dataSetId"; Expression={ $dataset.id }}, @{Name="dataSet"; Expression={ $dataset.name }}`
                        , @{Name="group"; Expression={ $workspace.name }}, @{Name="configuredBy"; Expression={ $dataset.configuredBy }} `                        

                    $dsRefreshHistoryGlobal += $dsRefreshHistory
                }
            }
            catch
            {
                $ex = $_.Exception

                Write-Error -message "Error processing dataset: '$($ex.Message)'" -ErrorAction Continue

                # If its unauthorized no need to advance to other datasets in this workspace

                if ($ex.Message.Contains("Unauthorized") -or $ex.Message.Contains("(404) Not Found"))
                {
                    Write-Host "Got unauthorized/notfound, skipping workspace"
                
                    break
                
                }
            }
        }
    }
    
    if ($dsRefreshHistoryGlobal.Count -gt 0)
    {
        $dsRefreshHistoryGlobal | ConvertTo-Json -Depth 5 | Out-File "$outputPath\workspaces.datasets.refreshes.json" -Force 
    }
}
finally
{
    $stopwatch.Stop()

    Write-Host "Ellapsed: $($stopwatch.Elapsed.TotalSeconds)s"
}