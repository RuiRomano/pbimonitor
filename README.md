
# Intro

For more information please watch the session [PBI Monitoring 101](https://youtu.be/viMLGEbTtog) (slides [here](https://github.com/RuiRomano/sessionslides/blob/main/PBIMonitoring101.pdf))

This project aims to provide a solution to collect activity & catalog data from your Power BI tenant using powershell scripts and a Power BI templates to analyse all this data.

You can deploy the powershell scripts in two ways:
- [As an Azure Function](#setup---as-an-azure-function) - Recommended
- [As a Local PowerShell in Server](#setup---as-a-local-powershell)


# Requirements

## Ensure you have the propper permissions

- A [Power BI Administrator](https://docs.microsoft.com/en-us/power-bi/admin/service-admin-role) account to change the [Tenant Settings](https://docs.microsoft.com/en-us/power-bi/guidance/admin-tenant-settings)
- Permissions to create an [Azure Active Directory Service Principal](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal) 
- Permissions to create/use an [Azure Active Directory Security Group](https://docs.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-groups-create-azure-portal)

## Create a Service Principal & Security Group

> [!NOTE]  
> Azure Active Directory is now call Entra ID.

On Azure Active Directory:

1. Go to "App Registrations" select "New App" and leave the default options
2. Generate a new "Client Secret" on "Certificates & secrets" and save the Secret text
3. Save the App Id & Tenant Id on the overview page of the service principal
4. Create a new Security Group on Azure Active Directory and add the Service Principal above as member
5. Optionally add the following API Application level permissions on "Microsoft Graph" API with Administrator grant to get the license & user info data:
    - User.Read.All
    - Directory.Read.All

        ![image](https://user-images.githubusercontent.com/10808715/142396742-2d0b6de9-95ef-4b2a-8ca9-23c9f1527fa9.png)
        ![image](./Images/SP_APIPermission_Directory.png)
        <img width="762" alt="image" src="https://user-images.githubusercontent.com/10808715/169350157-a9ccb47d-2c65-4b1a-80a1-757b9b02536d.png">


## Authorize the Service Principal on PowerBI Tenant

As a Power BI Administrator go to the Power BI Tenant Settings and authorize the Security Group on the following tenant settings:

- "Allow service principals to use read-only Power BI admin APIs"
- "Allow service principals to use Power BI APIs"
- "Enhance admin APIs responses with detailed metadata"
- "Enhance admin APIs responses with DAX and mashup expressions"

![image](https://user-images.githubusercontent.com/10808715/142396547-d7ca63e4-929c-4d8f-81c1-70c8bb6452af.png)

# API's Used

| Scope      | Resource | API
| ----------- | -------- |  ---------------- |
| Activity      | Power BI Activity Logs | [Admin API - Activity Events](https://docs.microsoft.com/en-us/rest/api/power-bi/admin/getactivityevents)
| Power BI Metadata  | Workspaces,DataSets,Reports,Dashboards,Permissions,Schema & Lineage | [Admin Scan API – GetModifiedWorkspaces](https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspace-info-get-modified-workspaces); [Admin Scan API – PostWorkspaceInfo](https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspace-info-post-workspace-info); [Admin Scan API – GetScanStatus (loop)](https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspace-info-get-scan-status); [Admin Scan API – GetScanResult](https://docs.microsoft.com/en-us/rest/api/power-bi/admin/workspace-info-get-scan-result)
| RefreshHistory      | Dataset Refresh History      | [Admin API - GetGroupsAsAdmin + Expand DataSets](https://docs.microsoft.com/en-us/rest/api/power-bi/admin/groups_getgroupsasadmin); [Dataset API - Get Refresh History](https://docs.microsoft.com/en-us/rest/api/power-bi/datasets/getrefreshhistoryingroup)
| Users & Licenses  | Users & Licenses; Licenses Details      | [Graph API – Users](https://docs.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0&tabs=http);[Graph API – SubscribedSKUs](https://docs.microsoft.com/en-us/graph/api/subscribedsku-list?view=graph-rest-1.0&tabs=http)
|Tenant Settings | Current Fabric Tenant Settings | [Fabric REST APIs / Tenants /  Tenants - Get Tenant Settings](https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/get-tenant-settings) |

<br>
<br>

# Setup - As an Azure Function

![image](https://user-images.githubusercontent.com/10808715/138757904-8be24316-d971-4b16-a31b-18b840e88d48.png)
*Fabric  API used for Tenant settings but does not require any other permissions for your Service Principal

On an Azure Subscription create a resource group:

![image](https://user-images.githubusercontent.com/10808715/138612805-a01c576d-1a59-4eed-b041-3bc5e0ff19d0.png)

All the resources should be created in the same region as the Power BI Tenant, to see the region of the Power BI tenant go to the About page on powerbi.com:

![image](https://user-images.githubusercontent.com/10808715/138612808-6e119c28-3bac-4b79-84ad-bd93088e9703.png)

Inside the Resource Group start a Function App Creation Wizard

![image](https://user-images.githubusercontent.com/10808715/138612821-6552a280-68f1-439f-bcb5-943a596d8518.png)

Basics
- Runtime - "PowerShell Core"
- Version 7.0

![image](https://user-images.githubusercontent.com/10808715/138612825-d6a18c1f-f6fd-429d-b96f-a9d9b867a3ee.png)

Hosting
- Storage Account - Create a new storage account to hold the data collected from the Azure Function
- Plan Type - Consumption

> [!NOTE]  
> On a large Power BI tenant a dedicated plan might be needed because on consumption the functions have a 10 minute timeout. Learn more about timeouts [here](https://learn.microsoft.com/en-us/azure/azure-functions/functions-scale#timeout) and how to extend the timeout configuration host.json [here](https://learn.microsoft.com/en-us/azure/azure-functions/functions-host-json).

![image](https://user-images.githubusercontent.com/10808715/138612831-424d1085-40f9-4c59-bb31-9195eca2d55e.png)


Monitoring
- Create a new AppInsights for logging & monitoring execution

![image](https://user-images.githubusercontent.com/10808715/138612834-2380c335-ec06-4a30-b05b-d591eee315dc.png)

In the end the resource group shall have the following resources:

![image](https://user-images.githubusercontent.com/10808715/138612841-79554c93-cdfa-49f4-bc0a-442674548a4b.png)

To deploy the Azure Function code you need to deploy the [AzureFunction.zip](./AzureFunction.zip) package:

![image](https://user-images.githubusercontent.com/10808715/138612851-dd146242-28cd-4535-a828-c1acf0118f50.png)

Open the Azure Function page, go to "Advanced Tools" and click "Go ➔" This will take you to a page called "Kudu Services"

![image](https://user-images.githubusercontent.com/10808715/138612856-e38ad2c9-a315-424e-b66b-0bb4b73dde63.png)

Go to "Tools" -> "Zip Push Deploy" and drag & drop the file [AzureFunction.zip](./AzureFunction.zip):

![image](https://user-images.githubusercontent.com/10808715/138612860-6c849c90-8c56-4c0d-b914-22cf8a6ba57a.png)
<br>
![image](https://user-images.githubusercontent.com/10808715/138612867-a3fbe8f9-bae0-412c-936b-f893da3c8c46.png)

Confirm if the deploy was successful:

![image](https://user-images.githubusercontent.com/10808715/138612872-273a4df9-474e-4186-9f97-6aae68dd07c0.png)

## Azure Function Configuration

Go back to the Azure Function page and click on "Configuration", and manually add the following settings:

| Setting      | Value | Description
| ----------- | ----------- |  --------- |
| PBIMONITOR_StorageConnStr      |      | Optional, only if you want to store data in a different storage from the Storage Account (setting 'AzureWebJobsStorage')  
| PBIMONITOR_AppDataPath      | C:\home\data\pbimonitor       | Path to AppData in Azure Function Disk, its where the state file is stored
| PBIMONITOR_ScriptsPath   | C:\home\site\wwwroot\Scripts        | Path to scripts on Azure Function Disk
| PBIMONITOR_ServicePrincipalId      | [YOUR SERVICE PRINCIPAL ID]       |
| PBIMONITOR_ServicePrincipalSecret  | [YOUR SERVICE PRINCIPAL SECRET]        |
| PBIMONITOR_ServicePrincipalTenantId | [YOUR TENANT ID]      |
| PBIMONITOR_ServicePrincipalEnvironment   | Public       | Power BI Cloud Environment
| PBIMONITOR_StorageContainerName | pbimonitor        | Name of the blob storage container
| PBIMONITOR_StorageRootPath   | raw       | Path on the storage container
| PBIMONITOR_FullScanAfterDays   | 30       | Number of Days to repeat a full scan - Optimization to avoid reading too many scanner files on the Power BI Dataset
| PBIMONITOR_CatalogGetModifiedParameters   |        | Optional, default: 'excludePersonalWorkspaces=false&excludeInActiveWorkspaces=true'
| PBIMONITOR_CatalogGetInfoParameters   |        | Optional, default: 'lineage=true&datasourceDetails=true&getArtifactUsers=true&datasetSchema=false&datasetExpressions=false'
| PBIMONITOR_GraphExtractGroups   | false       | Optional, if 'true' it will extract the members of the security groups to expand artifact permissions.

![image](https://user-images.githubusercontent.com/10808715/138612882-2b3c462b-5d0d-4606-b818-064819fcb7b9.png)
![image](https://user-images.githubusercontent.com/10808715/138612888-80438da3-5bb1-4c75-97f7-425cb804a03f.png)

### Enable Azure Azure Key Vault (Optional)

Its possible to store the Service Principal secret in Azure Key Vault, see the [documentation](https://docs.microsoft.com/en-gb/azure/app-service/app-service-key-vault-references?tabs=azure-cli) for more detail: 

Create a system assigned managed identity for your Azure function:

![image](https://user-images.githubusercontent.com/15087494/164741821-c3d9537f-4761-4506-a8c9-d0fc1c10ebb4.png)

Create your secrets in Azure Key Vault:

![image](https://user-images.githubusercontent.com/15087494/164742488-3837e48a-761b-4008-9605-c2c14f117d8c.png)

Add access policy for you system assigned managed identity created in your Azure function:

![image](https://user-images.githubusercontent.com/15087494/164743928-44f99b9c-91d9-4068-938b-97b79e1e085a.png)

Grant "Get" under "Secret Permissions":

![image](https://user-images.githubusercontent.com/15087494/164741243-9b205d59-5070-4f53-b210-2515182b4c67.png)

Reference your KeyVault on the Application Settings of Azure Function:

| Setting      | Value 
| ----------- | ----------- 
| PBIMONITOR_ServicePrincipalId      | @Microsoft.KeyVault(VaultName=myvault;SecretName=appid)       
| PBIMONITOR_ServicePrincipalSecret  | @Microsoft.KeyVault(VaultName=myvault;SecretName=pbilog)      
| PBIMONITOR_ServicePrincipalTenantId | @Microsoft.KeyVault(VaultName=myvault;SecretName=tenantid)    

![image](https://user-images.githubusercontent.com/15087494/164720874-91f230be-ed1e-465d-a8cc-ac36715323d9.png)


## Azure Function Time Triggers

The Azure Function has 4 time trigger functions enabled by default:

| Function      | Default Execution | Description
| ----------- | ----------- |  --------- |
| AuditsTimer      | Everyday at 2AM       | Fetches activity data from the Actitivy API
| CatalogTimer   | Everyday at 1AM    | Fetches metadata from the tenant: workspaces, datasets, reports,data sources
| DatasetRefreshTimer      | Everyday at 5AM  | Fetches the refresh history of all datasets in workspaces where the service principal is a Member
| GraphTimer  | Everyday at 4AM        | Fetches the User & License information from Graph API |
| TenantSettingsTimer| Everyday at 4am | Fetches Tenant Setting data from Fabric API |

The function should be ready to run, go to the function page and open the “AuditsTimer” and Run it:

![image](https://user-images.githubusercontent.com/10808715/138612898-51613dfb-50b5-426d-9ee1-b8314f901b74.png)
![image](https://user-images.githubusercontent.com/10808715/138612903-4e74625a-1fdc-4197-8034-621040b6b484.png)

### Change Azure Function Time Trigger

Its possible to change the time of the trigger by changing the 'function.json' file for each timer using App Service Editor:

![image](./Images/AzureFunction_TimerChange_AppService.png)

Or editing the timer integration:

![image](./Images/AzureFunction_TimerChange_Timer.png)

## Force a Full Scan

On large tenants you may run into memory issues reading all the data from a Power BI Dataset.

The PowerQuery of the PowerBI template was optimized to only read the scan files since the last full scan and the Azure Function setting 'PBIMONITOR_FullScanAfterDays' ensure a full scan will be executed every X days.

Its also possible to force a full scan by editing the State file (C:\home\data\pbimonitor\state.json) using [Kudo](https://docs.microsoft.com/en-us/azure/app-service/resources-kudu)

![image](./Images/Kudo_Statefile.png)

And remove properties: Catalog.LastRun, Catalog.LastFullScan (if exists)

![image](./Images/Kudo_Statefile2.png)

## Storage Account

If you dont want to use the built-in storage account of the Azure Function its possible to connect the Azure Function to another storage account by setting the connection string of the storage account in the configuration property: 'PBIMONITOR_StorageConnStr'

## Power BI Report Template

Open the Power BI Report template [PBI - Activity Monitor](./PBI%20-%20Activity%20Monitor%20-%20BlobStorage.pbit) and set the parameters:

Change the parameter "DataLocation" and write the blob storage name:

![image](https://user-images.githubusercontent.com/10808715/138612953-18b78a55-84a7-4361-aaa4-9ae979ffca4c.png)

You'll also need to copy the Access key from the Azure Portal:

![image](https://user-images.githubusercontent.com/37491308/143308677-31606ef2-2d2f-4725-8c44-337743a3eb6e.png)

And then paste it in the "Account key" box in the Azure Blob Storage credentials, which can be found in the Data Source Settings in Power BI Desktop:

![image](https://user-images.githubusercontent.com/37491308/143309293-7f164b7d-ecf1-49ec-9ad0-602472cc0a40.png)


![image](https://user-images.githubusercontent.com/10808715/130269811-a1083587-2eea-4615-90d5-8ade916fc471.png)

![image](https://user-images.githubusercontent.com/10808715/130269862-77293a90-bacf-4ac4-88a9-0d54efc07977.png)

![image](https://user-images.githubusercontent.com/10808715/130269931-1125f711-4074-4fd1-b607-29da153010a4.png)

## Incremental Refresh

By default the Power BI template will read all the activity files from the storage account, but those files are not updatable and a possible optimization is to enable [Incremental Refresh](https://docs.microsoft.com/en-us/power-bi/connect-data/incremental-refresh-overview) on the Activity Table.

The template is already prepared to support Incremental Refresh and filter only the new files, there is already a RangeStart & RangeEnd parameter:

![image](./Images/PBI_IncrementalRefresParams.png)

![image](./Images/PBI_IncrementalRefresFilter.png)

On the "Activity" table, enable Incremental Refresh with the desired configuration:

![image](./Images/PBI_IncrementalRefresConfig.png)

The Dataset refresh should be significantly faster in the service after this configuration.

# Setup - As a Local PowerShell

![image](https://user-images.githubusercontent.com/10808715/121097907-b0f53000-c7ec-11eb-806c-36a6b461a0d5.png)

## Install Required PowerShell Modules (as Administrator)
```
Install-Module -Name MicrosoftPowerBIMgmt -RequiredVersion 1.2.1026
```

## Configuration file

Open the [Config File](./Config.json) and write the saved properties from the Service Principal:
- AppId
- AppSecret
- Tenant Id 

![image](https://user-images.githubusercontent.com/10808715/142396344-67cdd1d3-1a4f-4838-baff-4422c4e86b56.png)

## Run 

The file [Fetch - Run](./Fetch%20-%20Run.ps1) is the entry point to call the other scripts.

Ensure [Fetch - Run](./Fetch%20-%20Run.ps1) is targeting the proper configuration file (parameter "configFilePath") and you can also control which scripts are executed on the parameter $scriptsToRun

Run [Fetch - Run](./Fetch%20-%20Run.ps1)

## Open the Power BI Report Template

Open the [Power BI Template file](./PBI%20-%20Activity%20Monitor%20-%20Disk.pbit) and change the parameter "DataLocation" to the data folder.
