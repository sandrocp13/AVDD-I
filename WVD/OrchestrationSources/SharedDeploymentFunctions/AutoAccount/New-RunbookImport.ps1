<#
.SYNOPSIS
Import and publish a new runbook to the given automation account

.DESCRIPTION
Import and publish a new runbook to the given automation account

.PARAMETER orchestrationFunctionsPath
Path to the functions folders at the root of the runbook script

.PARAMETER AutomationAccountName
The name of the automation account

.PARAMETER AutomationAccountRGName
The name of the resource group containing the automation account

.PARAMETER ScalingRunbookName
Name of the scaling runbook to create
#>
function New-RunbookImport {
    
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string] $orchestrationFunctionsPath,

        [Parameter(Mandatory)]
        [string] $AutomationAccountName,

        [Parameter(Mandatory)]
        [string] $AutomationAccountRGName,

        [Parameter(Mandatory)]
        [string] $ScalingRunbookName
    )

    Write-Verbose "=====================" -Verbose
    Write-Verbose "== CREATE RUNBOOK  ==" -Verbose

    $runbookImportInputObject = @{
        AutomationAccountName = $AutomationAccountName
        Name                  = $ScalingRunbookName
        Path                  = "$orchestrationFunctionsPath\AutoAccount\Runbooks\HostPoolScaling.ps1"
        ResourceGroupName     = $AutomationAccountRGName
        Type                  = 'PowerShell'
        Force                 = $true
    }
    if ($PSCmdlet.ShouldProcess("Runbook '$ScalingRunbookName'", "Import")) {
        Import-AzAutomationRunbook @runbookImportInputObject
    }

    Write-Verbose "=======================" -Verbose
    Write-Verbose "==  PUBLISH RUNBOOK  ==" -Verbose

    if ((Get-AzAutomationRunbook -ResourceGroupName $AutomationAccountRGName -AutomationAccountName $AutomationAccountName -Name $ScalingRunbookName).State -ne 'Published') {
        $publishRunbookInputObject = @{
            AutomationAccountName = $AutomationAccountName
            ResourceGroupName     = $AutomationAccountRGName
            Name                  = $ScalingRunbookName
        }
        if ($PSCmdlet.ShouldProcess("Runbook '$ScalingRunbookName'", "Publish")) {
            $null = Publish-AzAutomationRunbook @publishRunbookInputObject
            Write-Verbose "Published runbook" -Verbose
        }
    }
    else {
        Write-Verbose "Runbook '$ScalingRunbookName' already published" -Verbose
    }
}