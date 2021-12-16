
<#
.SYNOPSIS
Update/Add a table entry for the given VM

.DESCRIPTION
Update/Add a table entry for the given VM

.PARAMETER vmName
Mandatory. The VM entry to update. Acts as the row identifier

.PARAMETER hostpoolName
Mandatory. The name of the host pool. Used as a partition key

.PARAMETER propertyTuples
Mandatory. A hashtable of key value pairs to set/update

.PARAMETER stateTable
Mandatory. The storage table to update. Can be fetched via `$stateTable = Get-AzStorageTable –Name $stateTableName –Context $sa.Context`

.EXAMPLE
Set-TableProperty -vmname 'vm01' -hostpoolName 'hp' -propertyTuples @{ 'version' = '1.0.0' } -stateTable (Get-AzStorageTable –Name 'hostpool01Table' –Context (Get-AzStorageAccount -Name 'stateSa' -ResourceGroup 'stateSaRg').Context)

Add/Update the row with key 'vm01' and partition 'hp' in the storage account 'stateSa' table 'hostpool01Table' with the key value pair 'version: 1.0.0'
#>
function Set-TableProperty {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string] $vmName,
            
        [Parameter(Mandatory = $true)]
        [string] $hostpoolName,

        [Parameter(Mandatory = $true)]
        [hashtable] $propertyTuples,
            
        [Parameter(Mandatory = $true)]
        [object] $stateTable
    )

    $updateString = ($propertyTuples.Keys | Foreach-Object { "{0}: {1}" -f $_, $propertyTuples[$_] } ) -join '; '
    if (-not ($row = Get-AzStorageTableRowByPartitionKeyRowKey -table $stateTable -partitionKey $hostpoolName -rowKey $vmName -ErrorAction 'SilentlyContinue')) {
        # No row for this VM existing yet
        $addRowInputObject = @{
            table        = $stateTable 
            rowKey       = $vmName 
            property     = $propertyTuples
            partitionKey = $hostpoolName
        }
        if ($PSCmdlet.ShouldProcess(("Table entry [$vmName] with property [$updateString]"), 'Add')) {
            Add-AzStorageTableRow @addRowInputObject | Out-Null
        }
    }
    else {
        # Updating row for this VM
        foreach ($property in $propertyTuples.Keys) {
            if (-not (Get-Member -InputObject $row -Name $property -MemberType 'NoteProperty')) {
                Add-Member -InputObject $row -Name $property -Value $propertyTuples[$property] -MemberType 'NoteProperty'
            }
            else {
                if ([String]::IsNullOrEmpty($propertyTuples[$property])) {
                    $row.PSObject.Properties.Remove($property)
                }
                else {
                    $row.$property = $propertyTuples[$property]
                }
            }
        }
        if ($PSCmdlet.ShouldProcess("Table entry [$vmName] with property [$updateString]", 'Update')) {
            $row | Update-AzStorageTableRow -table $stateTable | Out-Null
        }
    }
}