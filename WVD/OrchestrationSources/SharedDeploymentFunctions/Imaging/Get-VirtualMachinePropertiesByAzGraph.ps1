<#
.SYNOPSIS
Gets the VM within the given resource group by leveraging AzGraph.

.DESCRIPTION
Gets the VM within the given resource group by leveraging AzGraph.

.PARAMETER ResourceGroupName
Required. The name of the resource group containing the VMs to be retrieved. 

.PARAMETER subscriptionId
Optional. The id of the subscription. Defaults to the current context.

.PARAMETER resourceType
Optional. The resource type of the resource to get. Defaults to 'Microsoft.Compute/virtualMachines'.

.PARAMETER resultWindowSize
Optional. The number of results Search-AzGraph will return at each iteration. Defaults to 1000.

.EXAMPLE
$hostPoolVMs = Get-VirtualMachinePropertiesByAzGraph -ResourceGroupName 'WVD-HostPool-01-TO-RG'

.LINK
https://docs.microsoft.com/en-us/powershell/module/az.resourcegraph/search-azgraph
#>
function Get-VirtualMachinePropertiesByAzGraph {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [string] $subscriptionId = (Get-AzContext).Subscription.Id,

        [Parameter(Mandatory = $false)]
        [string] $resourceType = 'Microsoft.Compute/virtualMachines',

        [Parameter(Mandatory = $false)]
        [int] $resultWindowSize = 1000
    )

    $iteration = 0
    $vmProperties = @()

    # Iterates until no VM is returned
    do {
        $iterationvm = @{}

        # Gets the first $resultWindowSize results in the first iteration
        if ($iteration -eq 0) {
            $iterationvm = Search-AzGraph -Query "Resources | where type =~ '$($resourceType)' and resourceGroup =~ '$($resourcegroupname)'" -First $resultWindowSize -Subscription "$($subscriptionId)"
        }
        # Gets the next $resultWindowSize results in each next iteration
        else {
            $skip = ($iteration * $resultWindowSize)
            $iterationvm = Search-AzGraph -Query "Resources | where type =~ '$($resourceType)' and resourceGroup =~ '$($resourcegroupname)'" -Skip $skip -First $resultWindowSize -Subscription "$($subscriptionId)"   
        }
        Write-Verbose "Iteration [$($iteration)]: Adding $($iterationvm.count) elements"
        Write-Verbose "Current VM count: $($vmProperties.count)"
        $vmProperties += $iterationvm
        $iteration++
    } while (-not $iterationvm.count -eq 0)

    return $vmProperties
}