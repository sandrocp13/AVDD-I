<#
.SYNOPSIS
Remove all Deployments in the given ResourceGroupName in an async way using jobs

.DESCRIPTION
Remove all Deployments in the given ResourceGroupName in an async way using jobs
    
.PARAMETER ResourceGroupName
Required. The name of the resource group containing the deployments to be removed

.PARAMETER ThrottleLimit
Optional. The maximum number of threads to start at the same time. Defaults to 30.

.EXAMPLE
Remove-RgDeployment -ResourceGroupName "WVD-HostPool-01-TO-RG" -ThrottleLimit 10

Removes all Deployments in the ResourceGroup "WVD-HostPool-01-TO-RG" using 10 jobs at a time
#>
function Remove-RgDeployment {
    
    param
    (
        [Parameter(Mandatory = $true)]
        [String] $ResourceGroupName,
    
        [Parameter(Mandatory = $false)]
        [int] $ThrottleLimit = 40
    )
    
    $ResourceGroup = Get-AzResourceGroup $ResourceGroupName -ErrorAction SilentlyContinue

    if ($ResourceGroup) {
        # Retrieve existing deployment metadata from the resourcegroup
        $deployments = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName
        Write-Verbose "Resource group $($ResourceGroupName): Found $($deployments.length) deployments. Deleting..." -Verbose

        # Delete existing deployment metadata from the resourcegroup
        $deploymentStatus = $deployments | Foreach-Object -ThrottleLimit $ThrottleLimit -AsJob -Parallel {  
            if ($_.ProvisioningState -eq "Succeeded") {
                try {
                    $status = Remove-AzResourceGroupDeployment -Name $_.DeploymentName -ResourceGroupName $($using:resourceGroupName)
                    if ($status -eq $true) {
                        Write-Verbose "Removal of $($_.DeploymentName) was successful" -Verbose
                    }
                    else {
                        Write-Verbose "Removal of $($_.DeploymentName) was unsuccessful" -Verbose
                    }
                }
                catch {
                    Write-Warning "Could not delete $($_.DeploymentName). Proceeding anyways. Error: $Error[0]"
                }  
            }
        }
        try {
            $res = $deploymentStatus | Wait-Job | Receive-Job
            Write-Verbose "$res" -Verbose
            Write-Verbose "Loop iteration done, beginning next iteration" -Verbose
        }
        catch {
            Write-Verbose "Loop iteration done, beginning next iteration. Error $Error[0]" -Verbose
        }
        
        # Retrieve existing deployment metadata from the resourcegroup after clean up
        $deployments = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName
        Write-Verbose "Resource group $($ResourceGroupName): Found $($deployments.length) deployments." -Verbose
    }
    else {
        Write-Verbose "Resource group $($ResourceGroupName) not found. No deployment to be deleted." -Verbose
    }
}
