# This script needs to be run on a domain joined machine that reaches both the DNS servers as well as the storage account IPs (via ER or VPN)

<#
.SYNOPSIS
This script manually domain joins the storage accounts in the target subscriptions and resourceGroupNames to the target domain.

.DESCRIPTION
Domain joins storage accounts as per input.

.PARAMETER resourceGroupName
Required. The name of the resource group containing the Storage Accounts. Note that you can also use a prefix or suffix in case you want to add records for several resource groups. E.g. use "myRg" if you want to add DNS records for all SAs in resourceGroups "myRG01" and "myRG02".

.PARAMETER subscriptionIds
Required. Id or Ids of the subscription(s) that contains the RG(s).

.PARAMETER domainName
Required. The name of the domain you want to join the storage accounts to (name of AAD domain).

.PARAMETER OEName
Required. The name of the organizational unit that the storage accounts should be associated to.

.EXAMPLE
Join-StorageAccountsToDomain -ResourceGroupName "MyRG" -subscriptionIds "1234-435345-23423" -domainName "mydomainname.com" -OEName "AVDStorageAccounts"

Updates the Subnet "WVD-Subnet-PE" in the VNet  "WVD-VNet-01" to allow the deployment of Private Endpoints. 
#>
function Join-StorageAccountsToDomain {
    
    param
    (
        [Parameter(Mandatory = $true)]
        [String] $resourceGroupName,
		
		[Parameter(Mandatory = $true)]
        [String] $subscriptionIds,
		
		[Parameter(Mandatory = $true)]
        [String] $domainName,
		
		[Parameter(Mandatory = $false)]
        [String] $OEName = "AVDStorageAccounts"
    )

	$requiredModule = "AzFilesHybrid"
	if (!(Get-Module $requiredModule)) {
		#install-module $module1
		import-module $requiredModule
	}

	foreach($subscriptionId in $subscriptionIds){
		Set-AzContext -Subscription $subscriptionId

		$profilesStorageAccountResourceGroupCol = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -match $resourceGroupName} | Select-Object ResourceGroupName | Foreach {"$($_.ResourceGroupName)"}

		foreach ($profilesStorageAccountResourceGroupName In $profilesStorageAccountResourceGroupCol){
			$storageAccountCollection = Get-AzStorageAccount -ResourceGroupName $profilesStorageAccountResourceGroupName
			$storageAccountNameCollection = $storageAccountCollection | Select-Object StorageAccountName | Foreach {"$($_.StorageAccountName)"}

			foreach ($str in $storageAccountNameCollection) {
				$storageAcc = Get-AzStorageAccount -Name $str -ResourceGroupName $profilesStorageAccountResourceGroupName #$resourceGroup
				$tempDomain = $storageAcc.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.DomainName
				if ($tempDomain -ne $domainName) { 
						join-AzStorageaccountForAuth -ResourceGroupName $profilesStorageAccountResourceGroupName -Name $str -DomainAccountType "ComputerAccount" -OrganizationalUnitName $OEName
				 }
				$storageaccount = Get-AzStorageAccount -ResourceGroupName $profilesStorageAccountResourceGroupName -Name $str
				$directoryServiceOptions = $storageAccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions
				$activeDirectoryProperties = $storageAccount.AzureFilesIdentityBasedAuth.ActiveDirectoryProperties
				Write-Host "Storage Account $str has properties directoryServiceOptions $directoryServiceOptions and activeDirectoryProperties $activeDirectoryProperties"
			}
		}
	}
}
