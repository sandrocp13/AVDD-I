<#
.SYNOPSIS
Attach SAS keys to matching references in the given file

.DESCRIPTION
Attach SAS keys to matching references <SAS> in the given file

.PARAMETER filePath
The path to the file to overwrite with SAS keys

.EXAMPLE
Set-SasKeysInFile -filePath C:/parameters.json

Replace any occurence of <SAS> in the given file containing for example:
{
	"type": "File",
	"name": "scriptExtensionMasterInstaller.ps1",
	"sourceUri": "https://<ReplaceWith-AssetsStorageAccountName>.blob.core.windows.net/<ReplaceWith-ImageContainerName>/scriptExtensionMasterInstaller.ps1<SAS>",
	"destination": "C:\\Windows\\Temp\\scriptExtensionMasterInstaller.ps1"
}
#>
function Set-SasKeysInFile {

	[CmdletBinding(SupportsShouldProcess)]
	param (
		[Parameter()]
		[string] $filePath
	)

	$parameterFileContent = Get-Content -Path $filePath
	$saslines = $parameterFileContent | Where-Object { $_ -like "*<SAS>*" } | ForEach-Object { $_.Trim() }

	Write-Verbose ("Found [{0}] lines with sas tokens (<SAS>) to replace" -f $saslines.Count)

	foreach ($line in $saslines) {
		Write-Verbose "Evaluate line [$line]" -Verbose
		$null = $line -cmatch "https.*<SAS>"
		$fullPath = $Matches[0].Replace('https://', '').Replace('<SAS>', '')
        $pathElements = $fullPath.Split('/')
        $containerName = $pathElements[1]
        $fileName = $pathElements[2]
        $storageAccountName = $pathElements[0].Replace('.blob.core.windows.net', '')

		$storageAccountResource = Get-AzResource -Name $storageAccountName -ResourceType 'Microsoft.Storage/storageAccounts'

		if(-not $storageAccountResource) {
			throw "Storage account [$storageAccountName] not found"
		}

		$storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccountResource.ResourceGroupName -Name $storageAccountName)[0].Value
		$storageContext = New-AzStorageContext $StorageAccountName -StorageAccountKey $storageAccountKey

		$sasToken = New-AzStorageBlobSASToken -Container $containerName -Blob $fileName -Permission 'r' -StartTime (Get-Date) -ExpiryTime (Get-Date).AddHours(2) -Context $storageContext

		$newString = $line.Replace('<SAS>', $sasToken)

		$parameterFileContent = $parameterFileContent.Replace($line, $newString)
	}

	if ($PSCmdlet.ShouldProcess("File in path [$filePath]", "Overwrite")) {
		Set-Content -Path $filePath -Value $parameterFileContent -Force
	}
}