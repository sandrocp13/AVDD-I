<#
.SYNOPSIS
Waits for all Deployments in the given ResourceGroupName to be completed (either succeeded or failed)

.DESCRIPTION
Waits for all Deployments in the given ResourceGroupName to be completed (either succeeded or failed)
    
.PARAMETER ResourceGroupName
Required. The name of the resource group containing the deployments to be completed

.EXAMPLE
Wait-RunningRgDeployment -ResourceGroupName "WVD-HostPool-01-TO-RG"

Waits for all Deployments in the ResourceGroup "WVD-HostPool-01-TO-RG" to be completed 
#>
function Wait-RunningRgDeployment {
    
    param
    (
        [Parameter(Mandatory = $true)]
        [String] $ResourceGroupName
    )
    
    $ResourceGroup = Get-AzResourceGroup $ResourceGroupName -ErrorAction SilentlyContinue

    if ($ResourceGroup) {
        Write-Verbose "Looking for active deployments in resource group $($ResourceGroupName) every minute until all are completed" -Verbose
        do {
            # Wait 1 minute
            Start-Sleep 60

            # Retrieve existing deployment metadata from the resourcegroup
            $rgDeployments = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

            # Filter deployments still running
            $activeDeployments = ($rgDeployments | Where-Object { $_.Provisioningstate -eq 'Running' }).DeploymentName

            Write-Verbose "Number of active deployments: $($activeDeployments.count)" -Verbose

            # Repeat until the number of active deployments is 0
        } while (-not($activeDeployments.count -eq 0))
    }
    else {
        Write-Verbose "Resource group $($ResourceGroupName) not found. No deployment to be deleted." -Verbose
    }
}