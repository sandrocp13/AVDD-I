<#
.SYNOPSIS
Updates a Subnet to disable Network Policies, which is a prerequisite in order to deploy Private Endpoints to this Subnet.

.DESCRIPTION
Sets a Subnet's PrivateEndpointNetworkPolicies to disabled in order to allow deployment of Private Endpoints. For more information please see here: https://docs.microsoft.com/en-us/azure/private-link/disable-private-endpoint-network-policy
    
.PARAMETER ResourceGroupName
Required. The name of the resource group containing the Virtual Network.

.PARAMETER vNetName
Required. The name of the Virtual Network which contains the Subnet for which the network policies will be updated.

.PARAMETER subNetName
Required. The name of the Subnet for which the network policies will be updated.

.PARAMETER subscriptionId
Optional. Id of the subscription that contains the RG / VNet. Only required if the subscription is not within the current Az-Context.

.EXAMPLE
Set-SubnetToAllowPrivateEndpoints -ResourceGroupName "WVD-HostPool-01-TO-RG" -vNetName "WVD-VNet-01" -subNetName "WVD-Subnet-PE"

Updates the Subnet "WVD-Subnet-PE" in the VNet  "WVD-VNet-01" to allow the deployment of Private Endpoints. 
#>
function Set-SubnetToAllowPrivateEndpoint {
    
    param
    (
        [Parameter(Mandatory = $true)]
        [String] $ResourceGroupName,
		
		[Parameter(Mandatory = $true)]
        [String] $vNetName,
		
		[Parameter(Mandatory = $true)]
        [String] $subNetName,
		
		[Parameter(Mandatory = $false)]
        [String] $subscriptionId = ""
    )
	
    if (-not ([string]::IsNullOrEmpty($subscriptionId))) {
		Set-AzContext -Subscription $subscriptionId
	}

	$virtualNetwork= Get-AzVirtualNetwork -Name $vNetName -ResourceGroupName $ResourceGroupName
	$privateEndpointStatus = ($virtualNetwork | Select -ExpandProperty subnets | Where-Object  {$_.Name -eq $subNetName} ).PrivateEndpointNetworkPolicies
	Write-Verbose "For subnet $subNetName privateEndpointNetworkPolicies currently set to $privateEndpointStatus" -verbose
	($virtualNetwork | Select -ExpandProperty subnets | Where-Object  {$_.Name -eq $subNetName} ).PrivateEndpointNetworkPolicies = "Disabled" 
	$virtualNetwork | Set-AzVirtualNetwork 
	$privateEndpointStatus = ($virtualNetwork | Select -ExpandProperty subnets | Where-Object  {$_.Name -eq $subNetName} ).PrivateEndpointNetworkPolicies
	Write-Verbose "For subnet $subNetName privateEndpointNetworkPolicies has now been set to $privateEndpointStatus" -verbose
}