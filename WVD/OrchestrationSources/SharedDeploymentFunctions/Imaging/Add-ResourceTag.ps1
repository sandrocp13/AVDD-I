<#
.SYNOPSIS
Add/Overwrite a tag for a given resource

.DESCRIPTION
Add/Overwrite a tag for a given resource. Does not remove any.

.PARAMETER resourceId
Id of the resource to add tags to

.PARAMETER name
Name of the tag

.PARAMETER value
Value of the tag

.EXAMPLE
Add-ResourceTag -resourceId '/subscriptions/<ReplaceWith-SubscriptionId>/resourceGroups/myRG' -name 'test' -value 'withTagValue'

Add the tag 'test = withTagValue' to resource group 'myRG'
#>
function Add-ResourceTag {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $resourceId,

        [Parameter(Mandatory)]
        [string] $name,

        [Parameter(Mandatory)]
        [string] $value
    )

    $existingTags = Get-AzTag -ResourceId $resourceId

    if ($existingTags.Properties.TagsProperty.Keys -contains $name) {
        $existingTags.Properties.TagsProperty.$name = $value
    }
    else {
        $existingTags.Properties.TagsProperty.Add($name, $value)
    }

    $null = New-AzTag -ResourceId $ResourceId -Tag $existingTags.Properties.TagsProperty
}