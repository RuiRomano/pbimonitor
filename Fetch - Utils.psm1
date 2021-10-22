function Add-FolderToBlobStorage
{
   [cmdletbinding()]
    param
    (
        [string]
        $storageAccountName,
        [string]
        $storageAccountKey,
        [string]
        $storageAccountConnStr,
        [string]
        $storageContainerName,
        [string]
        $storageRootPath,
        [string]
        $folderPath,
        [bool]
        $ensureContainer = $true
	)
        
    if ($storageAccountConnStr){
        $ctx = New-AzStorageContext -ConnectionString $storageAccountConnStr
    }
    else {
        $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    }
    
    if ($ensureContainer)
    {
        Write-Host "Ensuring container '$storageContainerName'"
        
        New-AzStorageContainer -Context $ctx -Name $storageContainerName -Permission Off -ErrorAction SilentlyContinue | Out-Null
    }

    $files = @(Get-ChildItem -Path $folderPath -Filter *.* -Recurse -File)
    
    Write-Host "Adding $($files.Count) files to blobstorage '$storageAccountName/$storageContainerName/$storageRootPath'"

    foreach($file in $files)
    {    
        $filePath = $file.FullName
        $fileName = (Split-Path $filePath -Leaf)        
        $parentFolder = (Split-Path $filePath -Parent)
        $relativeFolder = $parentFolder.Replace($folderPath,"").Replace("\","/").TrimStart("/").Trim();
    
        if(!([string]::IsNullOrEmpty($relativeFolder)))
        {
            $blobName = "$storageRootPath/$relativeFolder/$fileName"
        }
        else {
            $blobName = "$storageRootPath/$fileName"
        }
        
        Set-AzStorageBlobContent -File $filePath -Container $storageContainerName -Blob $blobName -Context $ctx -Force | Out-Null
    }
}
