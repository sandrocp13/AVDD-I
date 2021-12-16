<#
.SYNOPSIS
Remove the image templates and their temporary generated resource groups

.DESCRIPTION
Remove the image templates and their temporary generated resource groups

.PARAMETER resourcegroupName
Required. The resource group name the image template is deployed into

.PARAMETER imageTemplateName
Optional. The name of the image template. Defaults to '*'.

.PARAMETER Confirm
Request the user to confirm whether to actually execute any should process

.PARAMETER WhatIf
Perform a dry run of the script. Runs everything but the content of any should process

.EXAMPLE
Remove-ImageTemplate -resourcegroupName 'WVD-Imaging-TO-RG'

Search and remove the image template '*' and its generated resource group 'IT_WVD-Imaging-TO-RG_*'

.EXAMPLE
Remove-ImageTemplate -resourcegroupName 'WVD-Imaging-TO-RG' -imageTemplateName '19h2NoOffice'

Search and remove the image template '19h2NoOffice' and its generated resource group 'IT_WVD-Imaging-TO-RG_19h2NoOffice*'
#>
function Remove-ImageTemplate {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $resourcegroupName,

        [Parameter(Mandatory = $false)]
        [string] $imageTemplateName = ''
    )

    $imageTemplateInputObject = @{
        ResourceName      = "$imageTemplateName*" 
        ResourceGroupName = $ResourceGroupName 
        ResourceType      = 'Microsoft.VirtualMachineImages/imageTemplates'
        ErrorAction       = 'SilentlyContinue'
    }
    $imageTemplateResources = Get-AzResource @imageTemplateInputObject
    Write-Verbose ("Found [{0}] image templates to remove." -f $imageTemplateResources.Count) -Verbose
    
    foreach ($imageTemplateResource in $imageTemplateResources) {
        if ($PSCmdlet.ShouldProcess('Image template [{0}]' -f $imageTemplateResource.Name, "Remove")) {
            Remove-AzResource -ResourceId $imageTemplateResource.ResourceId -Force | Out-Null
        }
    }
}