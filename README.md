# Session Slides
PBI Monitoring 101 Session Slides: [here](https://github.com/RuiRomano/sessionslides/blob/main/PBIMonitoring101.pdf)


# Setup

1. Run "Setup - PreRequisites.ps1" (as admin)
2. Create a Service Principal (see slide 14 of [Presentation Slides](https://github.com/RuiRomano/sessionslides/blob/main/PBIMonitoring101.pdf#presentation))
3. Write the Service Principal AppId, AppSecret & Tenant ID on the configuration file: .\Config.json
4. Run the powershell scripts
5. Open the Power BI Template files and configure the parameter to target the '\data' folder

# Architecture

![image](https://user-images.githubusercontent.com/10808715/121097907-b0f53000-c7ec-11eb-806c-36a6b461a0d5.png)

# Reports

![image](https://user-images.githubusercontent.com/10808715/130269811-a1083587-2eea-4615-90d5-8ade916fc471.png)

![image](https://user-images.githubusercontent.com/10808715/130269862-77293a90-bacf-4ac4-88a9-0d54efc07977.png)

![image](https://user-images.githubusercontent.com/10808715/130269931-1125f711-4074-4fd1-b607-29da153010a4.png)

![image](https://user-images.githubusercontent.com/10808715/130269994-9797ffb6-a0fb-4006-91de-f87b0659b977.png)

![image](https://user-images.githubusercontent.com/10808715/130270131-d3fb1904-0fa7-429e-9673-eba728f501b2.png)

![image](https://user-images.githubusercontent.com/10808715/130270677-6e13011d-d561-4998-aebe-8d8a799eddf1.png)

# Azure Function Deploy

On an Azure Subscription create a resource group:

![image](resource group image)

All the resources should be created in the same region as the Power BI Tenant, to see the region of the Power BI tenant go to the About page on powerbi.com:

![image](Power BI About)

Inside the Resource Group start a Function App Creation Wizard

![image](Create Function App)

Basics
- Runtime - "PowerShell Core"
- Version 7.0

![image](Function App - Basics)

Hosting
- Storage Account - Create a new storage account to hold the data collected from the Azure Function
- Plan Type - Consumption, oon a large Power BI tenant a dedicated plan might be needed because on consumption the functions have a 10 minute timeout

![image](Function App - Hosting)

Monitoring
- Create a new AppInsights for logging & monitoring execution

![image](Function App - Monitoring)

In the end the resource group shall have the following resources:

![image](Resource Group Items)

To deploy the Azure Function code you need to run the script [Tool - PublishAzureFunction](./Tool%20-%20PublishAzureFunction.ps1). This script will create a zip file ready to deploy to the Azure Function:

![image](Run PowerShell)
![image](Zip File)

Open the Azure Function page and go to "Advanced Tools" -> "KUDO":

![image](KUDO)

Go to "Tools" -> "Zip Push Deploy" and drag & drop the file AzureFunction.zip:

![image](Push Deploy)

Confirm if the deploy was successful:

![image](Deploy Zip)

Go back to the Azure Function page and click on "Configuration", the following configuration settings must shall be created:

| Setting      | Value |
| ----------- | ----------- |
| PBIMONITOR_AppDataPath      | C:\home\data\pbimonitor       |
| PBIMONITOR_ScriptsPath   | C:\home\site\wwwroot\Scripts        |
| PBIMONITOR_ServicePrincipalId      | [YOUR SERVICE PRINCIPAL ID]       |
| PBIMONITOR_ServicePrincipalSecret  | [YOUR SERVICE PRINCIPAL SECRET]        |
| PBIMONITOR_ServicePrincipalTenantId | [YOUR TENANT ID]      |
| PBIMONITOR_ServicePrincipalEnvironment   | Public       |
| PBIMONITOR_StorageContainerName | pbimonitor        |
| PBIMONITOR_StorageRootPath   | raw       |

![image](Settings)

The function should be ready to run, go to the function page and open the “AuditsTimer” and Run it:

![image](Run)

A change to the Power BI file is required to work with the Blob Storage, open the PBIX and the Power Query window, go to the query "FilesProxy" and uncomment the queries "* from BlobStorage":

![image](FilesProxy)

Change the parameter "DataLocation" and write the blob storage name:

![image](Blob Storage Name)

Refresh the Dataset!