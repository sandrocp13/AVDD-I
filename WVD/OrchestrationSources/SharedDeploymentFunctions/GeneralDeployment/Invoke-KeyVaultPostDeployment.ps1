<#
.SYNOPSIS
Run the Post-Deployment for the key vault deployment

.DESCRIPTION
Run the Post-Deployment for the key vault deployment
- Add the secrets of the domain join user to the given key vault

.PARAMETER vaultName
Mandatory. Name of the deployed key vault

.PARAMETER domainJoin_UserName
Mandatory. Name of the user responsible to perform later domain joins

.PARAMETER domainJoin_pwd
Mandatory. Password for the given domain join user

.PARAMETER localAdminPassword
Optional. Default password for the SessionHost default admin

.PARAMETER storageJoin_UserName
Optional. Name of the synced identity responsible to perform later storage joins

.PARAMETER storageJoin_pwd
Optional. Password for the given storage join user

.PARAMETER Confirm
Will promt user to confirm the action to create invasible commands

.PARAMETER WhatIf
Dry run of the script

.EXAMPLE
Invoke-KeyvaultPostDeployment -vaultName "KeyVault" -domainJoin_UserName "TestUser" -domainJoin_pwd (ConvertTo-SecureString 'PickleRick' -AsPlainText -Force)

Create user 'TestUser' with its secret stored in the provided key vault 'KeyVault' and provide access to this key vault to the AD group 'KeyVaultAccessGroup'
#>
function Invoke-KeyvaultPostDeployment {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string] $orchestrationFunctionsPath,

        [Parameter(Mandatory)]
        [string] $vaultName,

        [Parameter(Mandatory)]
        [string] $domainJoin_userName,

        [Parameter(Mandatory)]
        [SecureString] $domainJoin_pwd,

        [Parameter(Mandatory = $false)]
        [string] $storageJoin_userName,

        [Parameter(Mandatory = $false)]
        [SecureString] $storageJoin_pwd,

        [Parameter(Mandatory = $false)]
        [SecureString] $localAdminPassword
    )

    begin {
        Write-Verbose ("[{0} entered]" -f $MyInvocation.MyCommand) -Verbose
        . "$orchestrationFunctionsPath\KeyVault\Add-KeyVaultCustomOrGeneratedSecret.ps1"
    }

    process {
        Write-Verbose "#################################################" -Verbose
        Write-Verbose "## 1 - Store secret for '$domainJoin_userName' ##" -Verbose
        Write-Verbose "#################################################" -Verbose

        $DomainJoinUserSecretInputObject = @{
            VaultName          = $vaultName
            secretName         = "$domainJoin_userName-Password"
            GenerateIfMissing  = $false
            customSecret       = $domainJoin_pwd
        }
        if ($PSCmdlet.ShouldProcess("Secret '$domainJoin_userName-Password' in key vault '$vaultName'", "Set")) {
            Add-KeyVaultCustomOrGeneratedSecret @DomainJoinUserSecretInputObject
        }

        Write-Verbose "####################################" -Verbose
        Write-Verbose "## 2 - Store local admin password ##" -Verbose
        Write-Verbose "####################################" -Verbose

        $LocalAdminSecretInputObject = @{
            VaultName          = $vaultName
            secretName         = 'localAdmin-Password'
            GenerateIfMissing  = $true
        }
        if ($localAdminPassword) {
            $LocalAdminSecretInputObject += @{
                customSecret = $localAdminPassword
            }
        }
        if ($PSCmdlet.ShouldProcess("Secret 'localAdmin-Password' in key vault '$vaultName'", "Set")) {
            Add-KeyVaultCustomOrGeneratedSecret @LocalAdminSecretInputObject
        }

        if (-not ([string]::IsNullOrEmpty($storageJoin_userName)) -and -not ([string]::IsNullOrEmpty($storageJoin_pwd))) {
            Write-Verbose "##################################################" -Verbose
            Write-Verbose "## 3 - Store secret for '$storageJoin_userName' ##" -Verbose
            Write-Verbose "##################################################" -Verbose

            $DomainJoinUserSecretInputObject = @{
                VaultName          = $vaultName
                secretName         = "$storageJoin_userName-Password"
                GenerateIfMissing  = $false
                customSecret       = $storageJoin_pwd
            }
            if ($PSCmdlet.ShouldProcess("Secret '$storageJoin_userName-Password' in key vault '$vaultName'", "Set")) {
                Add-KeyVaultCustomOrGeneratedSecret @DomainJoinUserSecretInputObject
            }
        }
        else {
            Write-Verbose "Storage join hybrid user credentials were not requested to be stored in the '$vaultName' key vault." -Verbose
        }
    }

    end {
        Write-Verbose ("[{0} existed]" -f $MyInvocation.MyCommand) -Verbose
    }
}

