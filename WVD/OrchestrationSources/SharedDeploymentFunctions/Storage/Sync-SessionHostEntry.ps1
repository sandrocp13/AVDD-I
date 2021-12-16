
<#
.SYNOPSIS
Sync the registered session hosts in a given host pool resource group with the actual deployed VMs. 
Optionally also sync the entries in the Host Pools state table.

.DESCRIPTION
Sync the registered session hosts in a given host pool resource group with the actual deployed VMs. 
Optionally also sync the entries in the Host Pools state table.

.PARAMETER hostPoolResourceGroupName
MAndatory. Name of the resource group hosting the host pool and VMs

.PARAMETER stateStorageAccountName
Optional. The name of the storage account hosting the host pool state. Provide if state table should by synced too.

.PARAMETER stateTableName
Optional. The name of the table in the storage account hosting the host pool state. Provide if state table should by synced too.

.PARAMETER orchestrationFunctionsPath
Path to the required functions

.EXAMPLE
Sync-SessionHostEntry -orchestrationFunctionsPath 'C:\dev' -hostPoolResourceGroupName 'WVD-HostPool-01-PO-RG'

Sync the deployed VMs with the entries registerd in the host pool in resource group 'WVD-HostPool-01-PO-RG'

.EXAMPLE
Sync-SessionHostEntry -orchestrationFunctionsPath 'C:\dev' -hostPoolResourceGroupName 'WVD-HostPool-01-PO-RG' -stateStorageAccountName 'wvdpoassetsstore' -stateTableName 'wvdpohp'

Sync the deployed VMs with the entries registerd in the host pool in resource group 'WVD-HostPool-01-PO-RG' and state table 'wvdpohp' in storage account 'wvdpoassetsstore'
#>
function Sync-SessionHostEntry {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string] $orchestrationFunctionsPath,

        [Parameter(Mandatory = $true)]
        [string] $hostPoolResourceGroupName,

        [Parameter(Mandatory = $false)]
        [string] $stateStorageAccountName,

        [Parameter(Mandatory = $false)]
        [string] $stateTableName
    )

    begin {            
        Write-Verbose ("[{0} entered]" -f $MyInvocation.MyCommand) -Verbose
        . "$orchestrationFunctionsPath\Storage\Remove-StateTableEntry.ps1"        
    }

    process {

        # Get VMs
        # --------------------------------
        $deployedVMs = Get-AzResource -ResourceGroupName $hostPoolResourceGroupName -ResourceType 'Microsoft.Compute/virtualMachines' -ErrorAction 'SilentlyContinue'
        if ($deployedVMs) {
            $deployedVMNames = $deployedVMs.Name
        }
        else {
            $deployedVMNames = @()
        }   

        # Cleanup Registered Session Hosts
        # --------------------------------
        # Get Host Pool Information
        $hostPool = Get-AzWvdHostPool -ResourceGroupName $hostPoolResourceGroupName -ErrorAction 'SilentlyContinue'
        if ($hostPool) {
            $registeredSessionHosts = Get-AzWvdSessionHost -HostPoolName $hostPool.Name -ResourceGroupName $hostPoolResourceGroupName -ErrorAction 'SilentlyContinue' | Sort-Object 'SessionHostName'

            foreach ($registeredSessionHost in $registeredSessionHosts) {
                $SessionHostName = $registeredSessionHost.Name.Split("/")[1]
                $VMName = $SessionHostName.split('.')[0]
                if ($deployedVMNames -notcontains $VMName) {
                    Write-Verbose "Registered session host [$VMName] maps to no deployed VM. Removing registration" -Verbose
                    if (($PSCmdlet.ShouldProcess("Registered session host [$VMName] from host pool [{0}]" -f $hostPool.Name), "Remove")) {
                        Remove-AzWvdSessionHost -ResourceGroupName $hostPoolResourceGroupName -Name $SessionHostName -HostPoolName $hostPool.Name -Force 
                    }
                }
            }

            if ($stateStorageAccountName) {
                ## Get Storage Table Information
                ## -----------------------------
                $stateStorageAccountResource = Get-AzResource -Name $stateStorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts'
                $stateStorageAccount = Get-AzStorageAccount -Name $stateStorageAccountName -ResourceGroupName $stateStorageAccountResource.ResourceGroupName
                $stateTable = Get-AzStorageTable -Name $stateTableName -Context $stateStorageAccount.Context
                $vmStateEntries = Get-AzStorageTableRowAll -table $stateTable

                # Cleanup StateTable
                # ------------------
                if ($stateTable) {
                    foreach ($vmStateEntry in $vmStateEntries) {
                        $stateTableVMName = $vmStateEntry.RowKey
                        if ($deployedVMNames -notcontains $stateTableVMName) {
                            Write-Verbose "StateTable entry [$stateTableVMName] maps to no deployed VM. Removing entry" -Verbose
                            if ($PSCmdlet.ShouldProcess("Statetable [$stateTableName] entry [$stateTableVMName]", "Remove")) {
                                Remove-StateTableEntry -vmname $stateTableVMName -hostpoolName $hostPool.Name -stateTable $stateTable
                            }
                        }
                    }
                }
                else {
                    Write-Verbose "State table [$stateTableName] not found in storage account [$stateStorageAccountName]" -Verbose
                }
            }
        }
        else {
            Write-Verbose "No host pool deployed in resource group [$hostPoolResourceGroupName]" -Verbose
        }
    }

    end {}
}