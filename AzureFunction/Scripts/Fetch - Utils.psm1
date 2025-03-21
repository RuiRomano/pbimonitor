function Add-FolderToBlobStorage {
    [cmdletbinding()]
    param
    (
        [string]
        $StorageAccountName,
        [string]
        $storageAccountKey,
        [string]
        $storageAccountConnStr,
        [string]
        $StorageAccountContainerName,
        [string]
        $storageRootPath,
        [string]
        $folderPath,
        [string]
        $rootFolderPath,
        [bool]
        $ensureContainer = $true
    )

    if ($storageAccountConnStr) {
        # If connection string is provided (legacy method)
        $ctx = New-AzStorageContext -ConnectionString $storageAccountConnStr
    }
    elseif ($StorageAccountName) {
        # Use Managed Identity if no shared key is provided
        Write-Host "Using Managed Identity for authentication to Storage Account '$StorageAccountName'"

        $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    }
    elseif ($StorageAccountKey) {
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    }
    else {
        throw "Storage account information is missing. Please provide StorageAccountName."
    }

    if ($ensureContainer) {
        Write-Host "Ensuring container '$env:PBIMONITOR_StorageContainerName'"

        New-AzStorageContainer -Context $ctx -Name $env:PBIMONITOR_StorageContainerName -Permission Off -ErrorAction SilentlyContinue | Out-Null
    }

    $files = @(Get-ChildItem -Path $folderPath -Filter *.* -Recurse -File)

    Write-Host "Adding folder '$folderPath' (files: $($files.Count)) to blobstorage '$StorageAccountName/$env:PBIMONITOR_StorageContainerName/$storageRootPath'"
    Write-Host "Root folder PATH: $rootFolderPath"
    if (!$rootFolderPath)
    {
        $rootFolderPath = $folderPath
    }

    foreach ($file in $files) {
        $filePath = $file.FullName

        Add-FileToBlobStorageInternal -ctx $ctx -filePath $filePath -storageRootPath $storageRootPath -rootFolderPath  $rootFolderPath
    }
}

function Add-FileToBlobStorage {
    [cmdletbinding()]
    param
    (
        [string]
        $StorageAccountName,
        [string]
        $storageAccountKey,
        [string]
        $storageAccountConnStr,
        [string]
        $StorageAccountContainerName,
        [string]
        $storageRootPath,
        [string]
        $filePath,
        [string]
        $rootFolderPath,
        [bool]
        $ensureContainer = $true
    )

    if ($storageAccountConnStr) {
        $ctx = New-AzStorageContext -ConnectionString $storageAccountConnStr
    }
    elseif ($StorageAccountName) {
        # Use Managed Identity if no shared key is provided
        Write-Host "Using Managed Identity for authentication to Storage Account '$StorageAccountName'"
        Write-Host "Ensuring container '$env:PBIMONITOR_StorageContainerName'"

        $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    }
    elseif ($StorageAccountKey) {
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    }
    else {
        throw "Storage account information is missing. Please provide StorageAccountName."
    }

    if ($ensureContainer) {
        Write-Host "Ensuring container '$env:PBIMONITOR_StorageContainerName'" # Worked with the env variable if its declared
        # Write-Host "Container Name: '$env:PBIMONITOR_StorageContainerName'"

        New-AzStorageContainer -Context $ctx -Name $env:PBIMONITOR_StorageContainerName -Permission Off -ErrorAction SilentlyContinue | Out-Null
    }

    Add-FileToBlobStorageInternal -ctx $ctx -filePath $filePath -storageRootPath $storageRootPath -rootFolderPath $rootFolderPath

}

function Add-FileToBlobStorageInternal {
    param
    (
        $ctx,
        [string]
        $storageRootPath,
        [string]
        $filePath,
        [string]
        $rootFolderPath
    )

    if (Test-Path $filePath) {
        Write-Host "Adding file '$filePath' files to blobstorage '$StorageAccountName/$env:PBIMONITOR_StorageContainerName/$storageRootPath'"
        Write-Host "File PATH: $filePath"
        Write-Host "Root folder PATH: $rootFolderPath"

        $filePath = Resolve-Path $filePath

        $filePath = $filePath.ToLower()

        if ($rootFolderPath) {
            $rootFolderPath = Resolve-Path $rootFolderPath
            $rootFolderPath = $rootFolderPath.ToLower()

            $fileName = (Split-Path $filePath -Leaf)
            $parentFolder = (Split-Path $filePath -Parent)
            Write-Host "Parent folder NAME: $parentFolder"
            $relativeFolder = $parentFolder.Replace($rootFolderPath, "").Replace("\", "/").TrimStart("/").Trim();
            Write-Host "Relative after TRIM: $relativeFolder"
        }

        if (!([string]::IsNullOrEmpty($relativeFolder))) {
            Write-Host "Relative folder PATH: $relativeFolder"
            $blobName = "$storageRootPath/$relativeFolder/$fileName"
        }
        else {
            Write-Host "Relative folder PATH: $relativeFolder in ELSE"
            $blobName = ("{0}/{1:yyyy}/{1:MM}/{1:dd}/{2}" -f $storageRootPath, (Get-Date), $fileName) # Forced to add the current date as folders if $relativeFolder empty
        }
        Write-Host "BLOB NAME: $blobName"
        Set-AzStorageBlobContent -File $filePath -Container $env:PBIMONITOR_StorageContainerName -Blob $blobName -Context $ctx -Force | Out-Null
    }
    else {
        Write-Host "File '$filePath' dont exist"
    }
}

function Get-ArrayInBatches
{
    [cmdletbinding()]
    param
    (
        [array]$array
        ,
        [int]$batchCount
        ,
        [ScriptBlock]$script
        ,
        [string]$label = "Get-ArrayInBatches"
    )

    $skip = 0

    $i = 0

    do
    {
        $batchItems = @($array | Select-Object -First $batchCount -Skip $skip)

        if ($batchItems)
        {
            Write-Host "[$label] Batch: $($skip + $batchCount) / $($array.Count)"

            Invoke-Command -ScriptBlock $script -ArgumentList @($batchItems, $i)

            $skip += $batchCount
        }

        $i++

    }
    while($batchItems.Count -ne 0 -and $batchItems.Count -ge $batchCount)
}

function Wait-On429Error
{
    [cmdletbinding()]
    param
    (
        [ScriptBlock]$script
        ,
        [int]$sleepSeconds = 3601
        ,
        [int]$tentatives = 1
    )

    try {

        Invoke-Command -ScriptBlock $script

    }
    catch {

        $ex = $_.Exception

        $errorText = $ex.ToString()
        ## If code errors at this location it is likely due to a 429 error. The PowerShell comandlets do not handle 429 errors with the appropriate message. This code will cover the known errors codes.
        if ($errorText -like "*Error reading JObject from JsonReader*" -or ($errorText -like "*429 (Too Many Requests)*" -or $errorText -like "*Response status code does not indicate success: *" -or $errorText -like "*You have exceeded the amount of requests allowed*")) {

            Write-Host "'429 (Too Many Requests)' Error - Sleeping for $sleepSeconds seconds before trying again" -ForegroundColor Yellow
            Write-Host "Printing Error for Logs: '$($errorText)'"
            $tentatives = $tentatives - 1

            if ($tentatives -lt 0)
            {
               throw "[Wait-On429Error] Max Tentatives reached!"
            }
            else
            {
                Start-Sleep -Seconds $sleepSeconds

                Wait-On429Error -script $script -sleepSeconds $sleepSeconds -tentatives $tentatives
            }
        }
        else {
            throw
        }
    }
}
