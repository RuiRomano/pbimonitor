#Requires -Modules @{ ModuleName="MicrosoftPowerBIMgmt"; ModuleVersion="1.2.1026" }

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

& "$currentPath\PBI - Activity Monitor - FetchActivity.ps1"

& "$currentPath\PBI - Activity Monitor - FetchCatalog.ps1"

& "$currentPath\PBI - Activity Monitor - FetchGraph.ps1"