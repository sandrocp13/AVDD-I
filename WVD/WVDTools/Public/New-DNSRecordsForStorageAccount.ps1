# This script needs to be run on a domain joined machine that reaches both the DNS servers as well as the storage account IPs (via ER or VPN)

<#
.SYNOPSIS
This script adds DNS records for Storage Accounts in case of an on-prem DNS (or IaaS DNS server in Azure). Note that this is not required if you use private DNS Zones.

.DESCRIPTION
Adds DNS A records for all Storage Accounts in a target Resource Group(s) to the target DNS servers.

.PARAMETER resourceGroupName
Required. The name of the resource group containing the Storage Accounts. Note that you can also use a prefix or suffix in case you want to add records for several resource groups. E.g. use "myRg" if you want to add DNS records for all SAs in resourceGroups "myRG01" and "myRG02".

.PARAMETER subscriptionId
Required. Id of the subscription that contains the RG(s).

.PARAMETER DNSName1
Required. The name of the first / primary DNS server where the DNS entries should be created.

.PARAMETER DNSName2
Required. The name of the second / replication DNS server where the DNS entries should be created.

.EXAMPLE
New-DNSRecordsForStorageAccounts -ResourceGroupName "MyRG" -subscriptionId "1234-435345-23423" -DNSName1 "VM01.mydomainname.com" -DNSName2 "VM02.mydomainname.com"

Updates the Subnet "WVD-Subnet-PE" in the VNet  "WVD-VNet-01" to allow the deployment of Private Endpoints. 
#>
function New-DNSRecordsForStorageAccount {
	
	    param
    (
        [Parameter(Mandatory = $true)]
        [String] $resourceGroupName,
		
		[Parameter(Mandatory = $true)]
        [String] $subscriptionId,
		
		[Parameter(Mandatory = $true)]
        [String] $DNSName1,
		
		[Parameter(Mandatory = $true)]
        [String] $DNSName2 
    )

	Connect-AzAccount

	Set-AzContext -SubscriptionId $subscriptionId


	##############################################
	### Get StorageAccount names and IP-addresses

	$profilesStorageAccountResourceGroupCol = Get-AzResourceGroup | Where-Object {$_.ResourceGroupName -match $resourceGroupName} | Select-Object ResourceGroupName | Foreach {"$($_.ResourceGroupName)"}

	foreach ($profStrAcc in $profilesStorageAccountResourceGroupCol) {
		$profilesStorageAccountResourceGroupName = $profStrAcc
		
		$endpointCollection = Get-AzPrivateEndpoint -ResourceGroupName $profilesStorageAccountResourceGroupName
		$endpointNameCollection = $endpointCollection| Select-Object Name| Foreach {"$($_.Name)"}

		foreach ($endpointname in $endpointNameCollection) {
		
			$endpoint = Get-AzPrivateEndpoint -Name $endpointname | Where-Object {$_.ResourceGroupName -match $resourceGroupName}
			$nic = Get-AzNetworkInterface -ResourceId $endpoint.NetworkInterfaces[0].id
			$StrAccIP = $nic.IpConfigurations[0].privateIpAddress
			$StrAccName = $endpoint.PrivateLinkServiceConnections[0].PrivateLinkServiceId.split("/") | Select-Object -Last 1
			
			#######################################
			### Update internal DNS records
			
			$ZoneName = "file.core.windows.net"
			
			# Add DNS record Host(A) to DNS-server DNSName1
			$GetDNSrecords = Get-DnsServerResourceRecord -ZoneName $ZoneName -ComputerName $DNSName1 | Select-Object HostName | Foreach {"$($_.HostName)"}
			if ($GetDNSrecords -contains $StrAccName) {
				write-verbose "$StrAccName already exists, updating $DNSName1" -verbose
				$OldObj = Get-DnsServerResourceRecord -Name $StrAccName -ZoneName $ZoneName -RRType "A" -ComputerName $DNSName1
				$NewObj = $OldObj.Clone()
				$newobj.recorddata.ipv4address=[System.Net.IPAddress]::parse($StrAccIP)
				Set-DnsServerResourceRecord -NewInputObject $NewObj -OldInputObject $OldObj -ZoneName $ZoneName -PassThru -ComputerName $DNSName1
			 } else {
				write-host "$StrAccName does not exist, creating with IP $StrAccIP... on $DNSName1"
				Add-DnsServerResourceRecordA -Name $StrAccName -ZoneName $ZoneName -ComputerName $DNSName1 -AllowUpdateAny -IPv4Address $StrAccIP
			}
			
			# Add DNS record Host(A) to DNS-server DNSName2
			$GetDNSrecords2 = Get-DnsServerResourceRecord -ZoneName $ZoneName -ComputerName $DNSName2 | Select-Object HostName | Foreach {"$($_.HostName)"}
			if ($GetDNSrecords2 -contains $StrAccName) {
				write-verbose "$StrAccName already exists, updating $DNSName2" -verbose
				$OldObj = Get-DnsServerResourceRecord -Name $StrAccName -ZoneName $ZoneName -RRType "A" -ComputerName $DNSName2
				$NewObj = $OldObj.Clone()
				$newobj.recorddata.ipv4address=[System.Net.IPAddress]::parse($StrAccIP)
				Set-DnsServerResourceRecord -NewInputObject $NewObj -OldInputObject $OldObj -ZoneName $ZoneName -PassThru -ComputerName $DNSName2
			 } else {
				write-verbose "$StrAccName does not exist, creating with IP $StrAccIP on $DNSName2..." -verbose
				Add-DnsServerResourceRecordA -Name $StrAccName -ZoneName $ZoneName -ComputerName $DNSName2 -AllowUpdateAny -IPv4Address $StrAccIP
			}
		}
	}

	# Verify
	$DNSRecords = @()
	$DNSRecords = Get-DnsServerResourceRecord -ZoneName $ZoneName -ComputerName $DNSName1
	$DNSRecords += Get-DnsServerResourceRecord -ZoneName $ZoneName -ComputerName $DNSName2
	Write-Verbose ($DNSRecords | Out-GridView) -Verbose
}	