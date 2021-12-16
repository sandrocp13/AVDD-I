
<#
.SYNOPSIS
Remove all VMs in the given ArrayList in an async way using jobs

.DESCRIPTION
Remove all VMs in the given ArrayList in an async way using jobs

.PARAMETER VmsToRemove
Optional. An ArrayList of the VMs to remove. Should contain VM instances (provided by 'Get-VirtualMachinePropertiesByRest')

.PARAMETER ResourceGroupName
The name of the resource group containing the VMs to remove.

.PARAMETER UtcOffset
Offset to UTC in hours

.PARAMETER ThrottleLimitShutDown
Optional. The maximum number of shut down threads to start at the same time. Defaults to 200.

.PARAMETER ThrottleLimitRemoval
Optional. The maximum number of removal threads to start at the same time. Defaults to 40.

.EXAMPLE
Remove-VirtualMachineByLoop -VmsToRemove ([ArrayList] Get-VirtualMachinePropertiesByRest -ResourcegroupName 'WVD-HostPool-TO-RG') -ResourcegroupName 'WVD-HostPool-TO-RG' -UtcOffset 1 -ThrottleLimit 10

Removes all VMs in the resource group with using 10 jobs at a time
#>
function Remove-VirtualMachineByLoop {

    param
    (
        [Parameter(Mandatory = $false)]
        [System.Collections.ArrayList] $VmsToRemove = @(),

        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $UtcOffset,

        [Parameter(Mandatory = $false)]
        [int] $ThrottleLimitShutDown = 200,

        [Parameter(Mandatory = $false)]
        [int] $ThrottleLimitRemoval = 40
    )

    begin {
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
        ##################
        ### MAIN LOGIC ###
        ##################

        # Converting date time from UTC to Local
        # $CurrentDateTime = Convert-UTCtoLocalTime -UtcOffset $UtcOffset
        [string[]]$TimeDiffHrsMin = "$($UtcOffset):0".Split(':')

        $maxWaitCount = 100
        $waitTimeSeconds = 30

        ##############
        ##    VM    ##
        ##############

        # Shut-down
        # ---------
        $vmStopJob = $VmsToRemove | Foreach-Object -ThrottleLimit $ThrottleLimitShutDown -AsJob -Parallel {
            Write-Output ("- [VM:{0}] Stop Azure VM [{0}]" -f $_.name)
            Stop-AzVM -Id $_.id -SkipShutdown -Force | Out-Null
        }
        Write-Log("ShutOff Output:")
        $vmStopJob | Receive-Job -Wait -ErrorAction 'SilentlyContinue'

        # Double check all intended VMs are deallocated
        $currentCount = 1
        $vmsInRgToShutDown = Get-VirtualMachinePropertiesByAzGraph -ResourceGroupName $ResourceGroupName -ErrorAction 'SilentlyContinue' | Where-Object { $_.Name -in $vmsToRemove.Name -and $_.Properties.extended.instanceView.powerState.displayStatus -eq "VM running" }
        do {
            if ($vmsInRgToShutDown.Count -eq 0) {
                Write-Log "  All relevant VMs are shut off"
                break
            }
            else {
                Write-Log ("  Remaining VMs: {0}" -f $vmsInRgToShutDown.Count)
                Write-Log "  Waiting $waitTimeSeconds seconds for VM shutdown [$currentCount|$maxWaitCount]"
                Start-Sleep $waitTimeSeconds
                $currentCount++
            }
            $vmsInRgToShutDown = Get-VirtualMachinePropertiesByAzGraph -ResourceGroupName $ResourceGroupName -ErrorAction 'SilentlyContinue' | Where-Object { $_.Name -in $vmsToRemove.Name -and $_.Properties.extended.instanceView.powerState.displayStatus -eq "VM running" }
        } while (($vmsInRgToShutDown.Count -gt 0) -and ($currentCount -le $maxWaitCount))

        # Removal
        # -------
        $vmRemovalJob = $VmsToRemove | Foreach-Object -ThrottleLimit $ThrottleLimitRemoval -AsJob -Parallel {
            Write-Output ("- [VM:{0}] Remove Azure VM [{0}]" -f $_.name)
            Remove-AzResource -ResourceId $_.id -Force | Out-Null
        }
        Write-Log("Removal Output:")
        $vmRemovalJob | Receive-Job -Wait -ErrorAction 'SilentlyContinue'

        # Double check all intended VMs are removed
        $currentCount = 1
        $refObjects = Get-AzResource -ResourceType 'Microsoft.Compute/virtualMachines' -ResourceGroupName $ResourceGroupName -ErrorAction 'SilentlyContinue'
        if ($refObjects -and $VmsToRemove) {
            do {
                $remainingVMCount = (Compare-Object -ReferenceObject $refObjects.Id -DifferenceObject $VmsToRemove.id -IncludeEqual -ExcludeDifferent).Count
                if ($remainingVMCount -eq 0) {
                    Write-Log "  All relevant VMs are removed"
                    break
                }
                else {
                    Write-Log "  Remaining VMs: $remainingVMCount"
                    Write-Log "  Waiting $waitTimeSeconds seconds for VM removal [$currentCount|$maxWaitCount]"
                    Start-Sleep $waitTimeSeconds
                    $currentCount++
                }
                $refObjects = Get-AzResource -ResourceType 'Microsoft.Compute/virtualMachines' -ResourceGroupName $ResourceGroupName -ErrorAction 'SilentlyContinue'
            } while (($remainingVMCount -gt 0) -and ($currentCount -le $maxWaitCount))
        }

        ########################
        ### SUB-VM-RESOURCES ###
        ########################

        # Collection information
        $nicObjects = @()
        $pipObjects = @()
        $osDiskObjects = @()
        $dataDisksObjects = @()

        foreach ($vmToRemove in $VmsToRemove) {
            # NIC
            $nicObjects += @{
                vmName = $vmToRemove.name
                id     = $vmToRemove.properties.networkProfile.networkInterfaces.id
            }

            # PIP
            if ($nic = Get-AzNetworkInterface -ResourceId $vmToRemove.properties.networkProfile.networkInterfaces.id -ErrorAction 'SilentlyContinue') {
                foreach ($ipConfig in $nic.IpConfigurations) {
                    if ($ipConfig.PublicIpAddress) {
                        $pipObjects += @{
                            vmName = $vmToRemove.name
                            id     = $ipConfig.PublicIpAddress.Id
                        }
                    }
                }
            }

            # OsDisk
            $osDiskObjects += @{
                vmName = $vmToRemove.name;
                id     = (Get-AzResource -ResourceType 'Microsoft.Compute/disks' -Name $vmToRemove.properties.storageProfile.osDisk.name -ResourceGroupName $ResourceGroupName).Id
            }

            # DataDisks
            if ($vmtoremove.properties.storageProfile.dataDisks.count -gt 0) {
                # Removing Data Disks for VM
                foreach ($dataDiskName in $vmToRemove.properties.storageProfile.dataDisks.name) {
                    $dataDisksObjects += @{
                        vmName = $vmToRemove.name;
                        id     = (Get-AzResource -ResourceType 'Microsoft.Compute/disks' -Name $dataDiskName -ResourceGroupName $ResourceGroupName).Id
                    }
                }
            }
        }

        Write-Log ("Nic to be removed: $($nicObjects.count)")
        Write-Log ("Pip to be removed: $($pipObjects.count)")
        Write-Log ("OSDisks to be removed: $($osDiskObjects.count)")
        Write-Log ("DataDisks to be removed: $($dataDisksObjects.count)")

        ############################
        ##     TRIGGER REMOVAL    ##
        ## NIC
        ## ---
        Write-Log("TRIGGER REMOVAL: NICs")
        $nicRemovalJob = $nicObjects | Foreach-Object {
            Write-Output ("- [VM:{0}] Remove Network Interface [{1}]" -f $_.vmName, (Split-Path $_.Id -Leaf))
            Remove-AzResource -ResourceId $_.Id -Force -AsJob | Out-Null
        }

        ## Public IP
        ## ---------
        Write-Log("TRIGGER REMOVAL: Public IPs")
        $pipRemovalJob = $pipObjects | Foreach-Object {
            Write-Output ("- [VM:{0}] Remove Public IP [{1}]" -f $_.vmName, (Split-Path $_.Id -Leaf))
            Remove-AzResource -ResourceId $_.Id -Force -AsJob | Out-Null
        }

        ## OS DISK
        ## -------
        Write-Log("TRIGGER REMOVAL: OsDisks")
        $osDiskRemovalJob = $osDiskObjects | Foreach-Object {
            Write-Output ("- [VM:{0}] Remove OS Disk [{1}]" -f $_.vmName, (Split-Path $_.Id -Leaf))
            Remove-AzResource -ResourceId $_.Id -Force -AsJob | Out-Null
        }

        ## DATA DISK
        ## ---------
        Write-Log("TRIGGER REMOVAL: DataDisks")
        $dataDiskRemovalJob = $dataDiskRemovalJob = $dataDisksObjects | Foreach-Object -ThrottleLimit $ThrottleLimitRemoval -AsJob -Parallel {
            Write-Output ("- [VM:{0}] Remove Data Disk [{1}]" -f $_.vmName, (Split-Path $_.Id -Leaf))
            Remove-AzResource -ResourceId $_.Id -Force -AsJob | Out-Null
        }

        #############################
        ##     WAIT FOR REMOVAL    ##
        ## NIC
        ## ---
        Write-Log("WAIT FOR REMOVAL: NIC")
        Write-Log("Removal Output:")
        if ($nicRemovalJob) { $nicRemovalJob | Receive-Job -Wait -ErrorAction 'SilentlyContinue' }
        else { Write-Log("- None") }

        # Double check all NICs are removed
        $currentCount = 1
        $refObjects = (Get-AzResource -ResourceType 'Microsoft.Network/networkInterfaces' -ResourceGroupName $ResourceGroupName).Id
        if ($refObjects -and $nicObjects) {
            do {
                $remainingNICsCount = (Compare-Object -ReferenceObject $refObjects -DifferenceObject $nicObjects.Id -IncludeEqual -ExcludeDifferent).Count
                if ($remainingNICsCount -eq 0) {
                    Write-Log "  All relevant NICs are removed"
                    break
                }
                else {
                    Write-Log "  Remaining NICs: $remainingNICsCount"
                    Write-Log "  Waiting [$waitTimeSeconds] for NIC removal [$currentCount|$maxWaitCount]"
                    Start-Sleep $waitTimeSeconds
                    $currentCount++
                }
                $refObjects = (Get-AzResource -ResourceType 'Microsoft.Network/networkInterfaces' -ResourceGroupName $ResourceGroupName).Id
            } while (($remainingNICsCount -gt 0) -and ($currentCount -le $maxWaitCount))
        }

        ## Public IP
        ## ---------
        Write-Log("WAIT FOR REMOVAL: Public IP")
        Write-Log("Removal Output:")
        if ($pipRemovalJob) { $pipRemovalJob | Receive-Job -Wait -ErrorAction 'SilentlyContinue' }
        else { Write-Log("- None") }

        # Double check all PIPs are removed
        $currentCount = 1
        $refObjects = (Get-AzResource -ResourceType 'Microsoft.Network/publicIPAddresse' -ResourceGroupName $ResourceGroupName).Id
        if ($refObjects -and $pipObjects) {
            do {
                $remainingPipCount = (Compare-Object -ReferenceObject $refObjects -DifferenceObject $pipObjects.Id -IncludeEqual -ExcludeDifferent).Count
                if ($remainingPipCount -eq 0) {
                    Write-Log "  All relevant Public IPs are removed"
                    break
                }
                else {
                    Write-Log("  Remaining PublicIPs: $remainingPipCount")
                    Write-Log "  Waiting [$waitTimeSeconds] for public IP removal [$currentCount|$maxWaitCount]"
                    Start-Sleep $waitTimeSeconds
                    $currentCount++
                }
                $refObjects = (Get-AzResource -ResourceType 'Microsoft.Network/publicIPAddresse' -ResourceGroupName $ResourceGroupName).Id
            } while (($remainingPipCount -eq 0) -and ($currentCount -le $maxWaitCount))
        }

        ## OS DISK
        ## -------
        Write-Log("WAIT FOR REMOVAL: OS Disk")
        Write-Log("Removal Output:")
        if ($osDiskRemovalJob) { $osDiskRemovalJob | Receive-Job -Wait -ErrorAction 'SilentlyContinue' }
        else { Write-Log("- None") }

        # Double check all OSDisks are removed
        $currentCount = 1
        $refObjects = (Get-AzResource -ResourceType 'Microsoft.Compute/disks' -ResourceGroupName $ResourceGroupName).Id
        if ($refObjects -and $osDiskObjects) {
            do {
                $remainingOsDiskCount = (Compare-Object -ReferenceObject $refObjects -DifferenceObject $osDiskObjects.Id -IncludeEqual -ExcludeDifferent).Count
                if ($remainingOsDiskCount -eq 0) {
                    Write-Log "  All relevant OS Disks are removed"
                    break
                }
                else {
                    Write-Log "  Remaining OSDisks: $remainingOsDiskCount"
                    Write-Log "  Waiting [$waitTimeSeconds] for osDisk removal [$currentCount|$maxWaitCount]"
                    Start-Sleep $waitTimeSeconds
                    $currentCount++
                }
                $refObjects = (Get-AzResource -ResourceType 'Microsoft.Compute/disks' -ResourceGroupName $ResourceGroupName).Id
            } while (($remainingOsDiskCount -gt 0) -and ($currentCount -le $maxWaitCount))
        }

        ## DATA DISK
        ## ---------
        Write-Log("WAIT FOR REMOVAL: Data Disks")
        Write-Log("Removal Output:")
        if ($dataDiskRemovalJob) { $dataDiskRemovalJob | Receive-Job -Wait -ErrorAction 'SilentlyContinue' }
        else { Write-Log("- None") }

    }
    end {}
}