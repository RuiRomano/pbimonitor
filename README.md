
# Intro

For more information please watch the session [PBI Monitoring 101](https://youtu.be/viMLGEbTtog) (slides [here](https://github.com/RuiRomano/sessionslides/blob/main/PBIMonitoring101.pdf))

This project aims to provide a solution to collect activity & catalog data from your Power BI tenant using powershell scripts and a Power BI templates to analyse all this data.

You can deploy the data collector powershell scripts in two ways:
- [Local on Windows](#setup---local-powershell)
- [As an Azure Function](#setup---as-an-azure-function)


# Setup - Local PowerShell

![image](https://user-images.githubusercontent.com/10808715/121097907-b0f53000-c7ec-11eb-806c-36a6b461a0d5.png)

### Install Required PowerShell Modules (as Administrator)
```
Install-Module -Name MicrosoftPowerBIMgmt -RequiredVersion 1.2.1026
```
### Create a Service Principal on Azure Active Directory

1. Go to "App Registrations" on Azure Active Directory and select "New App" and leave the default options
2. Generate a new "Client Secret" on "Certificates & secrets" and save the Secret text
3. Save the App Id & Tenant Id on the overview page of the service principal
4. Create a new Security Group on Azure Active Directory and add the Service Principal above as member
5.  Optionally add the following API's on "API Permissions" and Administrator grant to get the license & user info data:
    - User.Read.All
    - Organization.Read.All
6. As a Power BI Administrator go to the Power BI Tenant Settings and add the Security Group to the setting "Allow service principals to use read-only Power BI admin APIs". You should also enable the settings: "Enhance admin APIs responses with detailed metadata" and "Enhance admin APIs responses with DAX and mashup expressions"

### Change the Config.json

Open the [Config File](./Config.json) and write the AppId, AppSecret & Tenant Id from the Service Principal

### Run 

The file [Fetch - Run](./Fetch%20-%20Run.ps1) is the entry point to call the other scripts.

Ensure [Fetch - Run](./Fetch%20-%20Run.ps1) is targeting the proper configuration file (parameter "configFilePath") and you can also control which scripts are executed on the parameter $scriptsToRun

Run [Fetch - Run](./Fetch%20-%20Run.ps1)

### Open the Power BI Report

Open the [Power BI Template file](./PBI%20-%20Activity%20Monitor.pbit) and change the parameter "DataLocation" to the data folder.


# Setup - As an Azure Function

![image](https://user-images.githubusercontent.com/10808715/138757904-8be24316-d971-4b16-a31b-18b840e88d48.png)

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
- Plan Type - Consumption, oon a large Power BI tenant a dedicated plan might be needed because on consumption the functions have a 10 minute timeout

![image](https://user-images.githubusercontent.com/10808715/138612831-424d1085-40f9-4c59-bb31-9195eca2d55e.png)

Monitoring
- Create a new AppInsights for logging & monitoring execution

![image](https://user-images.githubusercontent.com/10808715/138612834-2380c335-ec06-4a30-b05b-d591eee315dc.png)

In the end the resource group shall have the following resources:

![image](https://user-images.githubusercontent.com/10808715/138612841-79554c93-cdfa-49f4-bc0a-442674548a4b.png)

To deploy the Azure Function code you need to run the script [Tool - PublishAzureFunction](./Tool%20-%20PublishAzureFunction.ps1). This script will create a zip file ready to deploy to the Azure Function:

![image](https://user-images.githubusercontent.com/10808715/138612849-23c8bdc7-1686-4d2b-a783-5d77e14ef591.png)
![image](https://user-images.githubusercontent.com/10808715/138612851-dd146242-28cd-4535-a828-c1acf0118f50.png)

Open the Azure Function page and go to "Advanced Tools" -> "KUDO":

![image](https://user-images.githubusercontent.com/10808715/138612856-e38ad2c9-a315-424e-b66b-0bb4b73dde63.png)

Go to "Tools" -> "Zip Push Deploy" and drag & drop the file AzureFunction.zip:

![image](https://user-images.githubusercontent.com/10808715/138612860-6c849c90-8c56-4c0d-b914-22cf8a6ba57a.png)
![image](https://user-images.githubusercontent.com/10808715/138612867-a3fbe8f9-bae0-412c-936b-f893da3c8c46.png)

Confirm if the deploy was successful:

![image](https://user-images.githubusercontent.com/10808715/138612872-273a4df9-474e-4186-9f97-6aae68dd07c0.png)

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

![image](https://user-images.githubusercontent.com/10808715/138612882-2b3c462b-5d0d-4606-b818-064819fcb7b9.png)
![image](https://user-images.githubusercontent.com/10808715/138612888-80438da3-5bb1-4c75-97f7-425cb804a03f.png)


The function should be ready to run, go to the function page and open the “AuditsTimer” and Run it:

![image](https://user-images.githubusercontent.com/10808715/138612898-51613dfb-50b5-426d-9ee1-b8314f901b74.png)
![image](https://user-images.githubusercontent.com/10808715/138612903-4e74625a-1fdc-4197-8034-621040b6b484.png)


A change to the Power BI file is required to work with the Blob Storage, open the PBIX and the Power Query window, go to the query "FilesProxy" and uncomment the queries "* from BlobStorage":

![image](https://user-images.githubusercontent.com/10808715/138612907-f49d5972-2bd2-4c2f-bf56-6273f07d54a8.png)

Change the parameter "DataLocation" and write the blob storage name:

![image](https://user-images.githubusercontent.com/10808715/138612953-18b78a55-84a7-4361-aaa4-9ae979ffca4c.png)


# Reports

![image](https://user-images.githubusercontent.com/10808715/130269811-a1083587-2eea-4615-90d5-8ade916fc471.png)

![image](https://user-images.githubusercontent.com/10808715/130269862-77293a90-bacf-4ac4-88a9-0d54efc07977.png)

![image](https://user-images.githubusercontent.com/10808715/130269931-1125f711-4074-4fd1-b607-29da153010a4.png)

