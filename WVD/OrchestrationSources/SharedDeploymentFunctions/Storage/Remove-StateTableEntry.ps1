<#
.SYNOPSIS
Remove a table entry for the given VM

.DESCRIPTION
Remove a table entry for the given VM

.PARAMETER vmName
Mandatory. The VM entry to remove. Acts as the row identifier

.PARAMETER hostpoolName
Mandatory. The name of the host pool. Used as a partition key

.PARAMETER stateTable
Mandatory. The storage table to update. Can be fetched via `$stateTable = Get-AzStorageTable –Name $stateTableName –Context $sa.Context`

.EXAMPLE
Remove-StateTableEntry -vmname 'vm01' -hostpoolName 'wvd-to-hp' -stateTable (Get-AzStorageTable –Name 'testcsehp' –Context (Get-AzStorageAccount -Name 'wvdadassetsstore' -ResourceGroup 'WVD-Mgmt-PO-RG').Context)

Remove the row with key 'vm01' and partition 'test-cse-h' from the storage account 'wvdadassetsstore' table 'testcsehp'
#>
function Remove-StateTableEntry {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string] $vmName,
            
        [Parameter(Mandatory = $true)]
        [string] $hostpoolName,
            
        [Parameter(Mandatory = $true)]
        [object] $stateTable
    )

    if ($PSCmdlet.ShouldProcess(("Table entry [$vmName] from partition [$hostpoolName]"), 'Remove')) {
        Remove-AzStorageTableRow -table $stateTable -partitionKey $hostpoolName -rowKey $vmName | Out-Null
    }
}