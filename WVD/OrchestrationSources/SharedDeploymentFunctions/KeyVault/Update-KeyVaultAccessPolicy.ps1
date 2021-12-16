<#
.SYNOPSIS
Update secret permissions for a specified identity in the target keyvault

.DESCRIPTION
Update secret permissions for a specified identity in the target keyvault
- If no permission is provided only get permissions for secrets are enabled by default
- If the -remove switch is provided the script will remove the identity from the keyvault access policies

.PARAMETER vaultName
Mandatory. Name of the key vault to handle.

.PARAMETER objectId
Mandatory. objectId of the identity to add.

.PARAMETER permissions
Optional. Permissions to secrets to be enabled. Get permissions are enabled by default.

.PARAMETER remove
Optional. If provided the script will remove the specified identity from the keyvault access policies.

.EXAMPLE
Update-KeyVaultAccessPolicy -vaultName 'wvd-kvlt' -objectId '11111111-aaaa-2222-bbbb-xxxxxxxxxxxx'

Add permission to get the keyvault secrets to the specified objectId

.EXAMPLE
Update-KeyVaultAccessPolicy -vaultName 'wvd-kvlt' -objectId '11111111-aaaa-2222-bbbb-xxxxxxxxxxxx' -remove

Remove the specified objectId from the keyvault access policies

#>
function Update-KeyVaultAccessPolicy {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string] $vaultName,

        [Parameter(Mandatory)]
        [string] $objectId,

        [Parameter(Mandatory = $false)]
        [string] $permissions = 'Get',

        [Parameter(Mandatory = $false)]
        [switch] $remove = $false
    )

    begin {
        Write-Debug ("[{0} entered]" -f $MyInvocation.MyCommand)
    }

    process {
        if ($remove) {
            $removeAccessPolicyInputObject = @{
                VaultName            = $vaultName
                ObjectId             = $objectId
            }
            if ($PSCmdlet.ShouldProcess("Identity $objectId from Key vault access policies", "Remove")) {
                Remove-AzKeyVaultAccessPolicy @removeAccessPolicyInputObject
                Write-Verbose "Wait 10 seconds for propagation" -Verbose
                Start-Sleep 10
            }
        }
        else {
            $addAccessPolicyInputObject = @{
                VaultName            = $vaultName
                ObjectId             = $objectId
                PermissionsToSecrets = $permissions
            }
            if ($PSCmdlet.ShouldProcess("Identity $objectId to Key vault access policies", "Add")) {
                Set-AzKeyVaultAccessPolicy @addAccessPolicyInputObject
                Write-Verbose "Wait 10 seconds for propagation" -Verbose
                Start-Sleep 10
            }
        }
    }

    end {
        Write-Debug ("[{0} existed]" -f $MyInvocation.MyCommand)
    }
}