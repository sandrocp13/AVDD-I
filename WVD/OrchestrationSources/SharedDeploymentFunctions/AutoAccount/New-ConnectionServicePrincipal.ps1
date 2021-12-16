function New-ConnectionServicePrincipal {

    param(
        [Parameter(Mandatory)]    
        [System.Security.Cryptography.X509Certificates.X509Certificate2] $PfxCert, 
            
        [Parameter(Mandatory)]
        [string] $applicationDisplayName,

        [Parameter(Mandatory = $false)]
        [string] $subscriptionId = (Get-AzContext).Subscription.Id
    )

    begin {
        Write-Debug ("[{0} entered]" -f $MyInvocation.MyCommand)
    }

    process {
        $servicePrincipal = Get-AzADServicePrincipal -DisplayName $applicationDisplayName

        $keyValue = [System.Convert]::ToBase64String($PfxCert.GetRawCertData())

        if (-not $servicePrincipal) { 
            Write-Verbose ("Service principal '{0}' not existing. Creating new." -f $applicationDisplayName) -Verbose

            $keyId = (New-Guid).Guid

            Write-Verbose 'Create an Azure AD application' -Verbose
            $Application = New-AzADApplication -DisplayName $ApplicationDisplayName -HomePage ("http://" + $applicationDisplayName) -IdentifierUris ("http://" + $keyId) 

            Write-Verbose 'Set app credential' -Verbose
            $null = New-AzADAppCredential -ApplicationId $Application.ApplicationId -CertValue $keyValue -StartDate $PfxCert.NotBefore -EndDate $PfxCert.NotAfter
        
            Write-Verbose 'Create SP' -Verbose
            $null = New-AzADServicePrincipal -ApplicationId $Application.ApplicationId # -Scope "/subscriptions/$subscriptionId" -Role 'Contributor'

            $serviceprincipal = Get-AzADServicePrincipal -ApplicationId $Application.ApplicationId
        }
        else {
            Write-Verbose ("Service principal '{0}' already existing. Updating certifiate." -f $applicationDisplayName) -Verbose
        
            # Reset App credential
            $null = Remove-AzADAppCredential -ApplicationId $servicePrincipal.ApplicationId -Force
            $null = New-AzADAppCredential -ApplicationId $servicePrincipal.ApplicationId -CertValue $keyValue -StartDate $PfxCert.NotBefore -EndDate $PfxCert.NotAfter
        }
        return $servicePrincipal.ApplicationId
    }

    end {
        Write-Debug ("[{0} existed]" -f $MyInvocation.MyCommand)
    }
}