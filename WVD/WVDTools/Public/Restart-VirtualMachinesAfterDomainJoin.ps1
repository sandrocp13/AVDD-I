
<#
.SYNOPSIS
Restart all Session Hosts in the given HostPoolName

.DESCRIPTION
Restart all Session Hosts in the given HostPoolName

.PARAMETER HostPoolName
Mandatory. Name of the hostpool to process

.PARAMETER ResourceGroupName
Mandatory.The name of the resource group containing the VMs to remove.

.PARAMETER ThrottleLimitRestart
Optional. The maximum number of restart threads to start at the same time. Defaults to 200.

.EXAMPLE
Restart-VirtualMachinesAfterDomainJoin -HostPoolName 'wvd-to-hp' -ResourcegroupName 'WVD-HostPool-TO-RG'

Restarts all 'wvd-to-hp' sessionhosts in the resource group
#>
function Restart-VirtualMachinesAfterDomainJoin {

    param
    (
        [Parameter(Mandatory = $true)]
        [string] $HostPoolName,

        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [int] $ThrottleLimitRestart = 200
    )

    begin {
		# Setting ErrorActionPreference to stop script execution when error occurs
        $ErrorActionPreference = "Stop"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Write-Verbose ("[{0} entered]" -f $MyInvocation.MyCommand) -Verbose
        #. "$orchestrationFunctionsPath\Imaging\Get-VirtualMachinePropertiesByAzGraph.ps1"
        #region Helper Functions
        function Get-LocalDateTime {
            return (Get-Date).ToUniversalTime().AddHours($TimeDiffHrsMin[0]).AddMinutes($TimeDiffHrsMin[1])
        }

        function Write-Log {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)]
                [string]$Message,

                [Parameter(Mandatory = $false)]
                [switch]$Err,

                [Parameter(Mandatory = $false)]
                [switch]$Warn
            )

            [string]$MessageTimeStamp = (Get-LocalDateTime).ToString('yyyy-MM-dd HH:mm:ss')
            $Message = "[$($MyInvocation.ScriptLineNumber)] $Message"
            [string]$WriteMessage = "$MessageTimeStamp $Message"

            if ($Err) {
                Write-Error $WriteMessage
                $Message = "ERROR: $Message"
            }
            elseif ($Warn) {
                Write-Warning $WriteMessage
                $Message = "WARN: $Message"
            }
            else {
                Write-Verbose $WriteMessage -Verbose
            }

            if (-not $LogAnalyticsWorkspaceId -or -not $LogAnalyticsPrimaryKey) {
                return
            }

            try {
                $body_obj = @{
                    'hostpoolName' = $HostPoolName
                    'logmessage'   = $Message
                    'TimeStamp'    = $MessageTimeStamp
                }
                $json_body = ConvertTo-Json -Compress $body_obj

                $laInputObject = @{
                    customerId     = $LogAnalyticsWorkspaceId
                    sharedKey      = $LogAnalyticsPrimaryKey
                    Body           = $json_body
                    logType        = 'WVDHostpoolUpdate_CL'
                    TimeStampField = 'TimeStamp'
                }

                $PostResult = Send-OMSAPIIngestionFile @laInputObject
                if ($PostResult -ine 'Accepted') {
                    throw "Error posting to OMS: $PostResult"
                }
            }
            catch {
                Write-Warning "$MessageTimeStamp Some error occurred while logging to log analytics workspace: $($PSItem | Format-List -Force | Out-String)"
            }
        }

        function Convert-UTCtoLocalTime {
            <#
            .SYNOPSIS
            Convert from UTC to Local time
            #>
            param(
                [Parameter(Mandatory)]
                [string] $UtcOffset
            )

            $UniversalTime = (Get-Date).ToUniversalTime()
            $UtcOffsetMinutes = 0
            if ($UtcOffset -match ":") {
                $UtcOffsetHours = $UtcOffset.Split(":")[0]
                $UtcOffsetMinutes = $UtcOffset.Split(":")[1]
            }
            else {
                $UtcOffsetHours = $UtcOffset
            }
            #Azure is using UTC time, justify it to the local time
            $ConvertedTime = $UniversalTime.AddHours($UtcOffsetHours).AddMinutes($UtcOffsetMinutes)
            return $ConvertedTime
        }
        #endregion
    }

    process {
        $maxWaitCount = 100
        $waitTimeSeconds = 30

        ##############
        ##    VM    ##
        ##############
		# Collect VM info
		# ---------
		$VmsToRemove = Get-VirtualMachinePropertiesByAzGraph -ResourceGroupName $ResourceGroupName -returnOnlyNewVms $true
		$SessionHosts = Get-AzWvdSessionHost -HostPoolName $HostpoolName -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Sort-Object Name

		$sessionHostVMs = @()
        foreach ($SessionHost in $SessionHosts) {
            $SessionHostName = $SessionHost.Name.Split("/")[1]
            $VMName = $SessionHostName.split('.')[0]
			$sessionHostVMs += $VMName
		}
		Write-Verbose "sessionHostVMs contains $sessionHostVMs" -Verbose

        # Restart
        # ---------
		Write-Verbose "There are $($VmsToRemove.count) VMs to restart" -Verbose
        $vmRestartJob = $VmsToRemove | Foreach-Object -ThrottleLimit $ThrottleLimitRestart -AsJob -Parallel {
            Write-Output ("- [VM:{0}] Restart Azure VM [{0}]" -f $_.name)
			$vmLocalName = $_.id.split("/")[8]
			if (-not ($vmLocalName -in $($using:sessionHostVMs) )){
				Restart-AzVM -Id $_.id
				Write-Output "Restart command issued to VM $($_.id) "
			} else {
				Write-Output "skipping VM $($_.id) as it is joined to host pool"
			}
        }
        #Write-Log("ShutOff Output:")
        $vmRestartJob | Receive-Job -Wait -ErrorAction 'SilentlyContinue'


    }
    end {}
}
