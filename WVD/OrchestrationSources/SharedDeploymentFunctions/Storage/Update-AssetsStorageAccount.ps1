<#
.SYNOPSIS
Run the Post-Deployment for the storage account deployment

.DESCRIPTION
Run the Post-Deployment for the storage account deployment
- Upload required data to the storage account

.PARAMETER orchestrationFunctionsPath
Mandatory. Path to the required functions

.PARAMETER storageContainerMapPath
Mandatory. Path to a json map configuring the setup of the container content for any storage account

.PARAMETER wvdUploadsPath
Mandatory. Path to the uploads folder hosting the files to be pushed to the containers

.PARAMETER resourceGroupPath
Optional. Path to the folder of the resource group. Only required of files need to be moved from there.

.PARAMETER hostPoolName
Optional. Name of the host pool the scripts are prepared for. Must be provided if no 'targetContainer' is specified in the 'storageContainerMap'
Special characters are removed to account for naming requirements.

.PARAMETER Confirm
Will promt user to confirm the action to create invasible commands

.PARAMETER WhatIf
Dry run of the script

.EXAMPLE
Update-AssetsStorageAccount -orchestrationFunctionsPath $currentDir -storageContainerMap $storageContainerMap -wvdUploadsPath $uploadFolderPath

Upload any required data to the storage account
#>
function Update-AssetsStorageAccount {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $orchestrationFunctionsPath,

        [Parameter(Mandatory = $true)]
        [string] $wvdUploadsPath,

        [Parameter(Mandatory = $false)]
        [string] $resourceGroupPath,

        [Parameter(Mandatory = $false)]
        [string] $hostPoolName,

        [Parameter(Mandatory = $true)]
        [string] $storageContainerMapPath
    )

    begin {
        Write-Verbose ("[{0} entered]" -f $MyInvocation.MyCommand) -Verbose
        . "$orchestrationFunctionsPath\Storage\Get-FileFromUrl.ps1"
        . "$orchestrationFunctionsPath\Storage\Compress-ContentFolder.ps1"
        . "$orchestrationFunctionsPath\Storage\Export-ContentToBlob.ps1"
    }

    process {

        if (-not (Test-Path $storageContainerMapPath)) {
            throw "Unable to locate file in path [$storageContainerMapPath]"
        }
        $storageContainerMap = ConvertFrom-Json (Get-Content -Path $storageContainerMapPath -Raw)


        # Prepare downloads folder (used for temporary software downloads)
        $downloadsFolderPath = Join-Path $wvdUploadsPath 'temp-wvd-downloads'
        if (-not (Test-Path $downloadsFolderPath)) {
            Write-Verbose "Creating folder [$downloadsFolderPath]" -Verbose
            New-Item -Path $downloadsFolderPath -ItemType 'Directory' | Out-Null
        }

        # Main logic
        foreach ($storageContainerMap in $storageContainerMap.storageContainerMaps) {
            
            $targetSAName = $storageContainerMap.storageAccount
            Write-Verbose "[S:$targetSAName] Processing storage account" -Verbose

            ## Evaluate Storage Account
            ## ------------------------
            if(-not ($storageAccountResource = Get-AzResource -Name $targetSAName -ResourceType 'Microsoft.Storage/storageAccounts')) {
                throw "Configured storage account [$targetSAName] not existing"
            }
            $storageAccount = Get-AzStorageAccount -Name $storageAccountResource.Name -ResourceGroupName $storageAccountResource.ResourceGroupName

            foreach ($containerMap in $storageContainerMap.containerMaps) {

                # Assembled files to remove after each container was processed
                $filesToRemove = [System.Collections.ArrayList]@()
                
                # Target folder for container zip files
                $tempZipsFolderPath = Join-Path $wvdUploadsPath 'WVDPackagesToUpload'
                if (-not (Test-Path $tempZipsFolderPath)) {
                    Write-Verbose "[S:$targetSAName] Creating folder [$tempZipsFolderPath]" -Verbose
                    New-Item -Path $tempZipsFolderPath -ItemType 'Directory' | Out-Null
                }

                # Target container to upload to
                if (-not ([String]::IsNullOrEmpty($containerMap.targetContainer))) {
                    $targetContainer = $containerMap.targetContainer
                }
                else {
                    if ([String]::IsNullOrEmpty($hostPoolName)) {
                        throw "Provide either the 'targetContainer' property as part of the container map, or the host pool name as an input parameter."
                    }
                    $targetContainer = $hostPoolName.ToLower()
                }
                Write-Verbose "[S:$targetSAName|C:$targetContainer] Processing container" -Verbose
                
                ## Evaluate Container
                ## ------------------
                if (-not (Get-AzStorageContainer -Name $targetContainer -Context $storageAccount.Context -ErrorAction 'SilentlyContinue')) {
                    Write-Warning "[S:$targetSAName|C:$targetContainer] Container is not existing in storage account and is created"
                    New-AzStorageContainer -Name $targetContainer -Context $storageAccount.Context | Out-Null
                }

                ## Assembling Files
                ## ----------------                 
                Write-Verbose "[S:$targetSAName|C:$targetContainer] Assembling Files" -Verbose
                foreach ($folderObject in $containerMap.packagesToUpload) {

                    ## package SOURCE
                    ## --------------
                    if ($folderObject -is [PSCustomObject]) {
                        $packageSourceName = $folderObject.packageName
                        $packageSourcePath = Join-Path $wvdUploadsPath $packageSourceName
                    }
                    elseif ($folderObject -is [string]) {
                        $packageSourceName = $folderObject
                        $packageSourcePath = Join-Path $wvdUploadsPath $packageSourceName
                    }
                    else {
                        throw "Unkown object type [$folderObject]"
                    }
                    Write-Verbose ("[S:$targetSAName|C:$targetContainer|F:$packageSourceName] Processing source folder") -Verbose
                    
                    ## OPTIONAL DOWNLOADS
                    ## ------------------
                    if ($folderObject.downloads -and $folderObject.downloads.count -gt 0) {
                        Write-Verbose "[S:$targetSAName|C:$targetContainer|F:$packageSourceName] Required downloads are configured and will be downloaded" -Verbose
                        foreach ($downloadObject in $folderObject.downloads) {

                            $downloadTargetPath = Join-Path $downloadsFolderPath $downloadObject.DestinationFilePath

                            if (-not (Test-Path $downloadTargetPath)) {
                                # Download to standard directory
                                $downloadInputObject = @{
                                    Url      = $downloadObject.Url
                                    FileName = $downloadTargetPath
                                }
                                if ($PSCmdlet.ShouldProcess(("File from url [{0}] to path [{1}]" -f $downloadInputObject.url, $downloadInputObject.FileName), "Download")) {
                                    Get-FileFromUrl @downloadInputObject -Verbose
                                }
                            }
                            else {
                                Write-Verbose "[S:$targetSAName|C:$targetContainer|F:$packageSourceName] File [$downloadTargetPath] already exists" -Verbose
                            }

                            # Copy to required directory
                            $copyItemInputObject = @{
                                Path        = $downloadTargetPath
                                Destination = Join-Path $packageSourcePath $downloadObject.DestinationFilePath
                                Force       = $true
                            }
                            if ($PSCmdlet.ShouldProcess(("File from [{0}] to [{1}]" -f $copyItemInputObject.Path, $copyItemInputObject.Destination), "Copy")) {
                                Copy-Item @copyItemInputObject | Out-Null
                            }
                        }   
                    }
                    
                    ## OPTIONAL ADDTIONAL CONFIGURATION FILES
                    ## --------------------------------------
                    if ($folderObject.additionalPackageFiles -and $folderObject.additionalPackageFiles.count -gt 0) {
                        Write-Verbose "[S:$targetSAName|C:$targetContainer|F:$packageSourceName] Additional files are configured and will be assembled" -Verbose
                        foreach ($configFilePath in $folderObject.additionalPackageFiles) {
                            # Move additional package file to package source path
                            $copyItemInputObject = @{
                                Path        = Join-Path (Join-Path $resourceGroupPath 'Parameters/Uploads') $configFilePath
                                Destination = Join-Path $packageSourcePath (Split-Path $configFilePath -Leaf)
                                Force       = $true
                            }
                            if ($PSCmdlet.ShouldProcess(("File from [{0}] to [{1}]" -f $copyItemInputObject.Path, $copyItemInputObject.Destination), "Copy")) {
                                Copy-Item @copyItemInputObject | Out-Null
                            }
                            $filesToRemove.Add($copyItemInputObject.Destination) | Out-Null
                        }
                    } 
                
                    ## COMPRESS FILES FOR CONTAINER
                    ## ----------------------------            
                    Write-Verbose "[S:$targetSAName|C:$targetContainer|F:$packageSourceName] Compress populated source folder" -Verbose
                    $compressionInputObject = @{
                        SourceFolderPath      = $packageSourcePath
                        DestinationFolderPath = $tempZipsFolderPath
                    }
                    if ($PSCmdlet.ShouldProcess(("Files in path [{0}] and store them in path [{1}\{2}.zip]" -f $compressionInputObject.SourceFolderPath, $compressionInputObject.DestinationFolderPath, (Split-Path $compressionInputObject.SourceFolderPath -LeafBase)), "Compress")) {
                        Compress-ContentFolder @compressionInputObject -Verbose
                    }
                }

                ## UPLOAD TO TARGET CONTAINER
                ## --------------------------   
                Write-Verbose "[S:$targetSAName|C:$targetContainer] Upload to target container" -Verbose
                $InputObject = @{
                    ResourceGroupName  = (Get-AzResource -Name $targetSAName -ResourceType 'Microsoft.Storage/storageAccounts').ResourceGroupName
                    StorageAccountName = $targetSAName
                    contentDirectories = $tempZipsFolderPath
                    targetContainer    = $targetContainer
                }
                if ($PSCmdlet.ShouldProcess("All data in path [$tempZipsFolderPath] to container [$targetContainer] in storage account [S:$targetSAName]", "Upload")) {
                    Export-ContentToBlob @InputObject -Verbose
                }

                ## CLEANUP
                ## ------- 
                Write-Verbose "[S:$targetSAName|C:$targetContainer] Removing assembled files" -Verbose
                foreach ($filePath in $filesToRemove) {
                    Write-Verbose ("[S:$targetSAName|C:$targetContainer] Removing file [{0}]" -f (Split-Path $filePath -Leaf)) -Verbose
                    if ($PSCmdlet.ShouldProcess("File from path [$filePath]", "Remove")) {
                        Remove-Item -Path $filePath -Force | Out-Null
                    }
                }
                if ($PSCmdlet.ShouldProcess("Temp folder for .zip files from path [$tempZipsFolderPath]", "Remove")) {
                    Remove-Item -Path $tempZipsFolderPath -Force -Recurse | Out-Null
                }
            }
        }

        # Remove downloads folder
        if ($PSCmdlet.ShouldProcess("Temporary downloads folder from path [$downloadsFolderPath]", "Remove")) {
            Remove-Item -Path $downloadsFolderPath -Force -Recurse | Out-Null
        }
    }
    
    end {
        Write-Verbose ("[{0} existed]" -f $MyInvocation.MyCommand)
    }
}