<#
.SYNOPSIS
Get the value of the given property from the state table

.DESCRIPTION
Get the value of the given property from the state table

.PARAMETER vmName
The VM entry to fetch. Acts as the row identifier

.PARAMETER hostpoolName
The name of the host pool. Used as a partition key

.PARAMETER property
Mandatory. The property to fetch (e.g. version). Correspondings to the table column

.PARAMETER stateTable
Mandatory. The storage table to fetch the data from. Can be fetched via `$stateTable = Get-AzStorageTable –Name $stateTableName –Context $sa.Context`

.EXAMPLE
Get-TableProperty -vmname 'vm01' -hostpoolName 'hp' -property 'version'-stateTable (Get-AzStorageTable –Name 'hostpool01Table' –Context (Get-AzStorageAccount -Name 'stateSa' -ResourceGroup 'stateSaRg').Context)

Get the value of the property 'version' of the row with key 'vm01' and partition 'hp' in the storage account 'stateSa' table 'hostpool01Table'

.EXAMPLE
Get-TableProperty -vmname 'vm01' -hostpoolName 'hp'-stateTable (Get-AzStorageTable –Name 'hostpool01Table' –Context (Get-AzStorageAccount -Name 'stateSa' -ResourceGroup 'stateSaRg').Context)

Get the all properties of the row with key 'vm01' and partition 'hp' in the storage account 'stateSa' table 'hostpool01Table'
#>
function Get-TableProperty {

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $vmName,
        
        [Parameter(Mandatory = $true)]
        [string] $hostpoolName,

        [Parameter(Mandatory = $false)]
        [string] $property = '',
        
        [Parameter(Mandatory = $true)]
        [object] $stateTable
    )

    if ($row = Get-AzStorageTableRowByPartitionKeyRowKey -table $stateTable -partitionKey $hostpoolName -rowKey $vmName -ErrorAction 'SilentlyContinue') {
        if ([string]::IsNullOrEmpty($property)) {    
            $propertiesTable = @{}
            $row.psobject.properties | ForEach-Object { $propertiesTable[$_.Name] = $_.Value }
            return $propertiesTable
        }
        else {
            return $row.$property
        }
    }
    else {
        return ''
    }
}