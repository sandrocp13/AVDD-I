<#
.SYNOPSIS
Remove all resources whose deployment in the given ResourceGroupName failed, in an async way using jobs

.DESCRIPTION
Remove all resources whose deployment in the given ResourceGroupName failed, in an async way using jobs

.PARAMETER orchestrationFunctionsPath
Required. Path to the required functions

.PARAMETER ResourceGroupName
Required. The name of the resource group containing the resources to be removed

.PARAMETER UtcOffset
Offset to UTC in hours

.PARAMETER ThrottleLimit
Optional. The maximum number of threads to start at the same time. Defaults to 30.

.EXAMPLE
Remove-FailedResource -ResourceGroupName "WVD-HostPool-01-TO-RG" -UtcOffset 1 -ThrottleLimit 10 

Removes all resources with a failed deployment in the ResourceGroup "WVD-HostPool-01-TO-RG" using 10 jobs at a time
#>
function Remove-FailedResource {
    
    param
    (
        [Parameter(Mandatory = $true)]
        [string] $orchestrationFunctionsPath,

        [Parameter(Mandatory = $true)]
        [String] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String] $UtcOffset,
    
        [Parameter(Mandatory = $false)]
        [int] $ThrottleLimit = 40
    )
    
    . "$orchestrationFunctionsPath\Imaging\Remove-VirtualMachineByLoop.ps1"

    $ResourceGroup = Get-AzResourceGroup $ResourceGroupName -ErrorAction SilentlyContinue

    if ($ResourceGroup) {

        $failedResources = @()
        $vmsToRemove = @()

        ########################
        # GET FAILED RESOURCES #
        ########################

        # Get all resource group deployments
        $rgDeployments = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName

        # Filter failed VM deployments 
        $failedDeployments = $rgDeployments | Where-Object { $_.Provisioningstate -eq 'failed' -and $_.DeploymentName -like "*vmLoop" }
        Write-Verbose "Number of failed deployments to fix $($failedDeployments.count)" -Verbose

        # Get resources whose deployment failed
        foreach ($failedDeployment in $failedDeployments) {
            try {
                # Get deployment operations for each failed deployment
                $deploymentsOps = Get-AzResourceGroupDeploymentOperation -DeploymentName $failedDeployment.DeploymentName -ResourceGroupName $ResourceGroupName
    
                # Filter failed operations and get related resourceIds to remove
                $resourceIds = ($deploymentsOps | Where-Object { $_.Provisioningstate -eq 'failed' }).TargetResource
                Write-Verbose "Deployment $($failedDeployment.DeploymentName): Number of failed resources $($resourceIds.count)" -Verbose
                $failedResources += $resourceIds
                    
            }
            catch {
                Write-Warning "Failure in getting $($failedDeployment.DeploymentName)'s deployments. Proceeding anyways. Error: $Error[0]"
            }
        }
        
        Write-Verbose "Total number of failed resources $($failedResources.count)" -Verbose
        
        ###############################
        # REMOVE VMS AND SUBRESOURCES #
        ###############################

        # Get VM resources from failed deployment operation target resource id
        foreach ($failedResource in $failedResources) {
            if ([string]::IsNullOrEmpty($failedResource) -ne $true) {  
                $resourceToRemove = Get-AzResource -ResourceId $failedResource -ErrorAction SilentlyContinue -ExpandProperties
                if ($resourceToRemove.ResourceType -eq "Microsoft.Compute/virtualMachines") {
                    $vm = Search-AzGraph -Query "Resources | where id =='$($resourceToRemove.ResourceId)'"
                    Write-Verbose "Adding vm $($vm.name) to the list of vms to remove" -Verbose
                    $vmsToRemove += $vm
                }
            }
        }
        Write-Verbose "Total number of existing vms to remove $($vmsToRemove.count)" -Verbose

        # Delete VMs
        if($vmsToRemove){
            Remove-VirtualMachineByLoop -VmsToRemove $vmsToRemove -ResourceGroupName $ResourceGroupName -UtcOffset $UtcOffset | Out-Null
        }
        else{
            Write-Verbose "No vm to remove" -Verbose
        }
        
        # Delete resources whose deployment failed
        $cleanUpStatus = $failedResources | Foreach-Object -ThrottleLimit $ThrottleLimit -AsJob -Parallel {  
            try {
                Write-Verbose "Deleting resource: $($_)" -Verbose
                Remove-AzResource -ResourceId $_ -Force
            }
            catch {
                Write-Warning "Could not delete $($_). Proceeding anyways. Error: $Error[0]"
            }
        }
        try {
            $res = $cleanUpStatus | Wait-Job | Receive-Job
            Write-Verbose "$res" -Verbose
            Write-Verbose "Loop iteration done, beginning next iteration" -Verbose
        }
        catch {
            Write-Verbose "Loop iteration done, beginning next iteration. Error $Error[0]" -Verbose
        }
    }
    else {
        Write-Verbose "Resource group $($ResourceGroupName) not found. No deployment to be deleted." -Verbose
    }
}
