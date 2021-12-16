<#
.SYNOPSIS
Store a given or generated secret in the target keyvault

.DESCRIPTION
Store a given or generated secret in the target keyvault.
- If no secret is provided and generation disabled, only its existence is checked
- If no secret is provided and generation enabled, a new password is generated and stored
- If a secret is provided and a key vault secret exists, both are compared. If it is diverges, the new secret is stored. Otherwise nothing happens.

.PARAMETER vaultName
Mandatory. Name of the key vault to handle

.PARAMETER secretName
Mandatory. Name of the secret

.PARAMETER customSecret
Optional. A custom secret to store in the keyvault. Must be a secure string.

.PARAMETER generateIfMissing
Optional. Control whether a new secret is generated if non is provided or found

.EXAMPLE
Add-KeyVaultCustomOrGeneratedSecret -vaultName 'myVault' -secretName 'myName' -customSecret (ConvertTo-SecureString 'MyPlaceholder' -AsPlainText -Force)

Store the secret 'myName' with value 'MyPlaceholder' in key vault 'myVault' if it is not yet existing
#>
function Add-KeyVaultCustomOrGeneratedSecret {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string] $vaultName,

        [Parameter(Mandatory)]
        [string] $secretName,

        [Parameter(Mandatory = $false)]
        [securestring] $customSecret,

        [Parameter(Mandatory = $false)]
        [switch] $generateIfMissing = $false
    )

    begin {
        Write-Debug ("[{0} entered]" -f $MyInvocation.MyCommand)
    }

    process {

        $InputObject = @{
            VaultName = $vaultName
            Name      = $secretName
        }

        $currentSecret = Get-AzKeyVaultSecret @InputObject

        if ($currentSecret) {
            Write-Verbose "A secret already exists in the keyvault." -Verbose
        
            if (-not [String]::IsNullOrEmpty($customSecret)) {
                Write-Verbose "A password was provided. Comparing" -Verbose
                $existingSecretMatches = $currentSecret.SecretValueText -eq (ConvertFrom-SecureString $customSecret -AsPlainText)
                if (-not $existingSecretMatches) {
                    Write-Verbose "Current secret and provided secret do not match. Override" -Verbose
                    $InputObject += @{
                        SecretValue = $customSecret
                    }
                }
            }
            else {
                Write-Verbose "No custom password was provided." -Verbose
            }
        }
        else {
            Write-Verbose "No secret exists in key vault" -Verbose
            if (-not [String]::IsNullOrEmpty($customSecret)) {
                Write-Verbose "A password was provided." -Verbose
                $InputObject += @{
                    SecretValue = $customSecret
                }
            }
            elseif($generateIfMissing) {
                Write-Verbose "Generating password" -Verbose
                $Password = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((New-Guid))))
                $userPassword = ConvertTo-SecureString -AsPlainText -Force $Password

                $InputObject += @{
                    SecretValue = $userPassword
                }
            } else {
                Write-Verbose "Password generation is disabled" -Verbose
            }
        }

        if ($InputObject['SecretValue']) {
            if ($PSCmdlet.ShouldProcess("Secret '$secretName' in key vault '$vaultName'", "Set")) {
                $null = Set-AzKeyVaultSecret @InputObject
                Write-Verbose "WVD Local Admin password secret setup invocation finished" -Verbose
            }
        }
        else {
            Write-Verbose "No further action required." -Verbose
        }
    }
    end {
        Write-Debug ("[{0} existed]" -f $MyInvocation.MyCommand)
    }
}