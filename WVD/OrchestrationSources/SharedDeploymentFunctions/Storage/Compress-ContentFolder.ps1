<#
.SYNOPSIS
Compress Scripts and Executable files to a zip archive.

.DESCRIPTION
This cmdlet performs compression for all content of the provided source folder into a specified destination folder.

.PARAMETER SourceFolderPath
Specifies the location containing the folder to be compressed.

.PARAMETER DestinationFolderPath
Specifies the target location for the final .zip file.

.PARAMETER CompressionLevel
Specifies how much compression to apply when creating the archive file. Fastest as default.

.PARAMETER Confirm
Will promt user to confirm the action to create invasible commands

.PARAMETER WhatIf
Dry run of the script

.EXAMPLE
Compress-ContentFolder -SourceFolderPath "\\path\to\sourcefolder" -DestinationFolderPath "\\path\to\destinationfolder"

Copy the scriptExtensionMasterInstaller.ps1 master script to location '\\path\to\destinationfolder'
Create an archive for files in path "\\path\to\sourcefolder" with the fastest compression level named "subfolder.zip" in the "\\path\to\destinationfolder".
#>
function Compress-ContentFolder {

    [CmdletBinding(SupportsShouldProcess = $True)]
    param(
        [Parameter(
            Mandatory,
            HelpMessage = "Specifies the location containing subfolders to be compressed."
        )]
        [string] $SourceFolderPath,

        [Parameter(
            Mandatory,
            HelpMessage = "Specifies the location for the .zip files."
        )]
        [string] $DestinationFolderPath,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Specifies how much compression to apply when creating the archive file. Fastest as default."
        )]
        [string] $CompressionLevel = "Fastest"
    )

    $masterInstallerFolderPath = Split-Path $SourceFolderPath -Parent
    $CSEMasterScriptSource = Join-Path $masterInstallerFolderPath "scriptExtensionMasterInstaller.ps1"
    $CSEMasterScriptDestination = Join-Path $DestinationFolderPath "scriptExtensionMasterInstaller.ps1"

    if (-not (Test-Path $CSEMasterScriptDestination)) {
        if ($PSCmdlet.ShouldProcess("Master installer file from [$CSEMasterScriptSource] to [$CSEMasterScriptDestination]", "Copy")) {
            Copy-Item -Path $CSEMasterScriptSource -Destination $CSEMasterScriptDestination
        }
    }

    Write-Verbose "## Create archive" -Verbose
    $destinationFilePath = "{0}.zip" -f (Join-Path $DestinationFolderPath (Split-Path $SourceFolderPath -LeafBase))
    $sourceFilePath = Join-Path $SourceFolderPath "*"

    Write-Verbose "Working on subfolder $SourceFolderPath" -Verbose
    Write-Verbose "Archive will be created from path $sourceFilePath" -Verbose
    Write-Verbose "Archive will be stored as $destinationFilePath" -Verbose
            
    $CompressInputObject = @{
        Path             = $sourceFilePath
        DestinationPath  = $destinationFilePath
        CompressionLevel = $CompressionLevel   
        Force            = $true 
        ErrorAction      = 'Stop'
    }

    Write-Verbose "Starting compression...." -Verbose
    if ($PSCmdlet.ShouldProcess("Required files from $sourceFilePath to $destinationFilePath", "Compress")) {
        Compress-Archive @CompressInputObject
    }
    Write-Verbose "Compression completed." -Verbose
}