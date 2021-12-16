<#
.SYNOPSIS
Run the Image Update process for the given host pool resource

.DESCRIPTION
Run the Image Update process for the given host pool resource
- Update the host pool

.PARAMETER HostPoolName
Mandatory. Name of the hostpool to process

.PARAMETER HostPoolRGName
Mandatory. Resource group of the hostpool to process

.PARAMETER LogoffDeadline
Mandatory. Logoff Deadline in yyyyMMddHHmm

.PARAMETER LogOffMessageTitle
Mandatory. Title of the popup the users receive when they get notified of their dawning session cancelation

.PARAMETER LogOffMessageBody
Mandatory. Message of the popup the users receive when they get notified of their dawning session cancelation

.PARAMETER UtcOffset
Offset to UTC in hours

.PARAMETER DeleteVMDeadline
Optional. Controls when to delete the host pool VMs (Very Destructive) in yyyyMMddHHmm

.PARAMETER MarketplaceImageVersion
Optional. Version of the used marketplace image. Mandatory if 'CustomImageReferenceId' is not provided.

.PARAMETER MarketplaceImagePublisher
Optional. Publisher of the used marketplace image. Mandatory if 'CustomImageReferenceId' is not provided.

.PARAMETER MarketplaceImageOffer
Optional. Offer of the used marketplace image. Mandatory if 'CustomImageReferenceId' is not provided.

.PARAMETER MarketplaceImageSku
Optional. Sku of the used marketplace image. Mandatory if 'CustomImageReferenceId' is not provided.

.PARAMETER MarketplaceImageLocation
Optional. Location of the used marketplace image. Mandatory if 'CustomImageReferenceId' is not provided and 'MarketplaceImageVersion' equals 'latest'.

.PARAMETER CustomImageReferenceId
Optional. Full Reference to Custom Image.
/subscriptions/<SubscriptionID>/resourceGroups/<ResourceGroupName>/providers/Microsoft.Compute/galleries/<ImageGalleryName>/images/<ImageDefinitionName>/versions/<version>
Mandatory if 'MarketplaceImageVersion' is not provided.

.PARAMETER LAWorkspaceName
Optional. Name of the LA workspace to send logs to

.PARAMETER stateStorageAccountName
Optional. The name of the storage account hosting the host pool state

.PARAMETER stateTableName
Optional. The name of the table in the storage account hosting the host pool state

.PARAMETER Confirm
Optional. Will promt user to confirm the action to create invasible commands

.PARAMETER WhatIf
Optional. Dry run of the script

.PARAMETER orchestrationFunctionsPath
Path to the required functions

.EXAMPLE
Update-WVDHostPool -HostPoolName 'wvd-to-hp' -HostPoolRGName 'WVD-HostPool-01-PO-RG' -LogoffDeadline '202007042000' -LogOffMessageTitle 'Kidding' -LogOffMessageBody 'Just' -UtcOffset '1' -stateStorageAccountName 'wvdassetssa' -stateTableName 'wvdtohp' -customImageReferenceId '/subscriptions/<ReplaceWith-SubscriptionId>/resourceGroups/WVD-Imaging-PO-RG/providers/Microsoft.Compute/galleries/aaddsgallery/images/W10-19H2-O365-AADDS/versions/0.24322.55884'

Invoke the update host pool orchestration script with the given parameters
#>
function Update-WVDHostPool {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $orchestrationFunctionsPath,

        [Parameter(Mandatory = $true)]
        [string] $HostPoolName,

        [Parameter(Mandatory = $true)]
        [string] $HostPoolRGName,

        [Parameter(Mandatory = $true)]
        [string] $LogOffMessageTitle,

        [Parameter(Mandatory = $true)]
        [string] $LogOffMessageBody,

        [Parameter(Mandatory = $true)]
        [string] $UtcOffset,

        [Parameter(Mandatory = $false)]
        [string] $DeleteVMDeadline = (Get-Date -Format 'yyyyMMddHHmm'), # Removal Deadline in yyyyMMddHHmm

        [Parameter(Mandatory = $true, ParameterSetName = 'MarketplaceImage')]
        [string] $MarketplaceImageVersion,

        [Parameter(Mandatory = $true, ParameterSetName = 'MarketplaceImage')]
        [string]$MarketplaceImagePublisher,

        [Parameter(Mandatory = $true, ParameterSetName = 'MarketplaceImage')]
        [string]$MarketplaceImageOffer,

        [Parameter(Mandatory = $true, ParameterSetName = 'MarketplaceImage')]
        [string]$MarketplaceImageSku,

        [Parameter(Mandatory = $false, ParameterSetName = 'MarketplaceImage')]
        [string]$MarketplaceImageLocation,

        [Parameter(Mandatory = $true, ParameterSetName = 'CustomSIGImage')]
        [string] $CustomImageReferenceId,

        [Parameter(Mandatory = $false)]
        [string] $LogoffDeadline = (Get-Date -Format 'yyyyMMddHHmm'), # Logoff Deadline in yyyyMMddHHmm

        [Parameter(Mandatory = $true)]
        [string] $stateStorageAccountName,

        [Parameter(Mandatory = $true)]
        [string] $stateTableName,

        [Parameter(Mandatory = $false)]
        [string] $LAWorkspaceName = ""
    )

    begin {
        # Setting ErrorActionPreference to stop script execution when error occurs
        $ErrorActionPreference = "Stop"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Write-Verbose ("[{0} entered]" -f $MyInvocation.MyCommand) -Verbose
        . "$orchestrationFunctionsPath\Imaging\Remove-VirtualMachineByLoop.ps1"
        . "$orchestrationFunctionsPath\Imaging\Get-VirtualMachinePropertiesByAzGraph.ps1"
        . "$orchestrationFunctionsPath\Imaging\Add-ResourceTag.ps1"
        . "$orchestrationFunctionsPath\Storage\Get-TableProperty.ps1"
        . "$orchestrationFunctionsPath\Storage\Set-TableProperty.ps1"
        . "$orchestrationFunctionsPath\Storage\Remove-StateTableEntry.ps1"

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

        function Stop-SessionHost {
            <#
            .SYNOPSIS
            Stop the Session Host
            #>
            param(
                [Parameter(Mandatory)]
                [string] $VMName
            )

            try {
                Get-AzVM -Name $VMName | Stop-AzVM -Force -NoWait | Out-Null
            }
            catch {
                Write-Log "ERROR: Failed to stop Azure VM: $($VMName) with error: $($_.exception.message)"
                Write-Error ($_.exception.message)
            }
        }

        function Set-ResourceGroupLifecycleTag {

            <#
            .SYNOPSIS
            Set resource group level tags to inform about the host pools resource state

            .DESCRIPTION
            The tags help to get an overview of the host-pools state on a resource group level. Tags that are assigned are:
            - LifecycleState = Consistent
            - LifecycleState = UpdateInitialized
            - LifecycleState = UpdateCompleted
            - LifecycleState = RequiresReRun

            .PARAMETER HostPoolName
            Name of the host pool to check

            .PARAMETER HostPoolRGName
            Manadatory. Name of the resource group the host pool is in. This is the one that gets the tags

            .PARAMETER TargetImageVersion
            Manadatory. The image version the host pool VMs should have that are considered up-to-date

            .PARAMETER ShutDownVMDeadlinePassed
            Mandatory. Flag to specify whether the deadline for deprecated host pool VMs to shut down has already passed

            .EXAMPLE
            Set-ResourceGroupLifecycleTag -HostPoolRGName 'WVD-HostPool-01-PO-RG' -HostPoolName 'wvd-to-hp' -TargetImageVersion '0.24322.55884' -ShutDownVMDeadlinePassed $false

            Evaluate the current state of the host pool 'wvd-to-hp' VMs and set the flags accordingly. The deadline for deprecated VMs to be force shut-down has not yet passed.
            #>
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [Parameter(Mandatory)]
                [string] $HostPoolName,

                [Parameter(Mandatory)]
                [string] $HostPoolRGName,

                [Parameter(Mandatory)]
                [string] $TargetImageVersion,

                [Parameter(Mandatory)]
                [bool] $ShutDownVMDeadlinePassed,

                [Parameter(Mandatory = $true)]
                [object] $stateTable
            )

            $lifecycleTagName = 'LifecycleState'
            $lifecycleTagValueConsistent = 'Consistent'
            $lifecycleTagValueUpdateInit = 'UpdateInitialized'
            $lifecycleTagValueUpdateCom = 'UpdateCompleted'
            $lifecycleTagValueReRun = 'RequiresReRun'

            $resourceGroup = Get-AzResourceGroup -Name $HostPoolRGName
            $sessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolRGName -ErrorAction SilentlyContinue | Sort-Object 'SessionHostName'

            # Case 1 : No VMs are deployed
            if (-not $sessionHosts) {
                if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueConsistent] on resource group $HostPoolRGName", "Set")) {
                    Write-Log "No session hosts deployed. Host Pool is consistent."
                    Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueConsistent
                }
                return
            }

            $outdatedVMs = Get-VirtualMachinePropertiesByAzGraph -ResourceGroupName $HostPoolRGName | Foreach-Object {
                Get-TableProperty -vmname $_.Name -hostpoolName $HostpoolName -stateTable $stateTable -property $ImageVersionPropName
            } | Where-Object {
                $_ -ne $TargetImageVersion
            }

            # Case 2 : No outdated VMs exist
            if ($outdatedVMs.count -eq 0) {
                if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueConsistent] on resource group $HostPoolRGName", "Set")) {
                    Write-Log "Session hosts are deployed, but no outdated VMs exist"
                    Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueConsistent
                }
                return
            }

            # Handle case: Deadline has not passed yet
            if (-not $ShutDownVMDeadlinePassed) {
                # Case 3 : Any VMs does not meet ($VMInstance.ImageVersion -ne $TargetImageVersion)
                $case2VMs = $outdatedVMs | Where-Object { ($_.properties.extended.instanceView.powerState.displayStatus -eq 'VM running' -or $_.properties.extended.instanceView.powerState.displayStatus -eq 'VM starting') }
                if ($case2VMs.Count -gt 0) {
                    if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueUpdateInit] on resource group $HostPoolRGName", "Set")) {
                        Write-Log "Setting ResourceGroup-Tag. Host Pool image update was initialized."
                        Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueUpdateInit
                    }
                    return
                }
                else {
                    # Case 4 If we have old VMs, but they are all already either deallocating or deallocated
                    if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueUpdateCom] on resource group $HostPoolRGName", "Set")) {
                        Write-Log "Setting ResourceGroup-Tag. Host Pool image update was initialized, but all outdated VMs are already shutting/shut down. Update is completed."
                        Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueUpdateCom
                    }
                    return
                }
            }
            # Handle case: Deadline has passed
            else {
                $case3VMs = $outdatedVMs | Where-Object { ($_.properties.extended.instanceView.powerState.displayStatus -eq 'VM deallocated' -or $_.properties.extended.instanceView.powerState.displayStatus -eq 'VM deallocating') }
                if ($case3VMs.Count -eq $outdatedVMs.Count) {
                    # Case 5 : VMs post deadline that aren't active anymore, but still exist
                    if ($case3VMs.Count -gt 0) {
                        if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueUpdateCom] on resource group $HostPoolRGName", "Set")) {
                            Write-Log "Setting ResourceGroup-Tag. Host pool image update completed."
                            Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueUpdateCom
                        }
                        return
                    }
                    # Case 6 : No more VMs post deadline that don't match latest image
                    else {
                        if ($PSCmdlet.ShouldProcess("Tag '[$lifecycleTagName = $lifecycleTagValueConsistent] on resource group $HostPoolRGName", "Set")) {
                            Write-Log "Setting ResourceGroup-Tag. No outdated VMs left in the host pool. State is consistent."
                            Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueConsistent
                        }
                        return
                    }
                }
                else {
                    if ($PSCmdlet.ShouldProcess("Log entry that update was not successful and ask for re-run.", "Add")) {
                        Write-Log "WARNING: VMs should be deallocated, but are not (yet). Please re-run" -Warn
                        Add-ResourceTag -resourceId $resourceGroup.ResourceId -name $lifecycleTagName -value $lifecycleTagValueReRun
                    }
                    else {
                        Add-LogEntry -LogMessageObj @{ hostpool = $HostpoolName; msg = "VMs should be deallocated, but are not (yet). Please re-run" }
                    }
                    return
                }
            }
        }
        #endregion
    }

    process {

        ##################
        ### MAIN LOGIC ###
        ##################

        # Converting date time from UTC to Local
        $CurrentDateTime = Convert-UTCtoLocalTime -UtcOffset $UtcOffset
        [string[]]$TimeDiffHrsMin = "$($UtcOffset):0".Split(':')

        ## Storage Table
        ## -------------
        $stateStorageAccountResource = Get-AzResource -Name $stateStorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts'
        $stateStorageAccount = Get-AzStorageAccount -Name $stateStorageAccountName -ResourceGroupName $stateStorageAccountResource.ResourceGroupName
        $stateTable = Get-AzStorageTable –Name $stateTableName –Context $stateStorageAccount.Context

        ### PropertyNames
        $ImageVersionPropName = 'ImageVersion'
        $NoScalingPropName = 'NoScaling'
        $DrainModePropName = 'DrainMode'

        ## Log Analytics
        ## -------------
        if (-not [String]::IsNullOrEmpty($LAWorkspaceName)) {
            if (-not ($LAWorkspace = Get-AzOperationalInsightsWorkspace | Where-Object { $_.Name -eq $LAWorkspaceName })) {
                throw "Provided log analytic workspace doesn't exist in your Subscription."
            }

            $WorkSpace = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $LAWorkspace.ResourceGroupName -Name $LAWorkspaceName -WarningAction Ignore
            $LogAnalyticsPrimaryKey = $Workspace.PrimarySharedKey
            $LogAnalyticsWorkspaceId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $LAWorkspace.ResourceGroupName -Name $LAWorkspaceName).CustomerId.GUID
        }

        if ($LogAnalyticsWorkspaceId -and $LogAnalyticsPrimaryKey) {
            Write-Verbose "Log analytics is enabled" -Verbose
        }

        # Calculate Image Version from Parameters
        if ($PSCmdlet.ParameterSetName -eq 'MarketplaceImage') {
            if ($MarketplaceImageVersion -eq 'latest') {
                $getImageInputObject = @{
                    Location      = $MarketplaceImageLocation
                    PublisherName = $MarketplaceImagePublisher
                    Offer         = $MarketplaceImageOffer
                    Sku           = $MarketplaceImageSku
                }
                $availableVersions = Get-AzVMImage @getImageInputObject | Select-Object Version
                $latestVersion = (($availableVersions.Version -as [Version[]]) | Measure-Object -Maximum).Maximum
                Write-Log "Running with Marketplace Image version [$latestVersion]"
                [Version]$TargetImageVersion = $latestVersion
            }
            else {
                Write-Log "Running with Marketplace Image version [$MarketplaceImageVersion]"
                [Version]$TargetImageVersion = $MarketplaceImageVersion
            }
        }
        else {
            Write-Log "Running with Custom Image"
            $ACustomImageID = $CustomImageReferenceId.Split("/")
            [Version]$TargetImageVersion = $ACustomImageID[$ACustomImageID.Count - 1]
        }

        ## Handle user session DeadlineTime
        $DeadlineDateTime = [System.DateTime]::ParseExact($LogoffDeadline, 'yyyyMMddHHmm', $null)
        ## Set Force Logoff if at or after deadline
        if ($CurrentDateTime -ge $DeadlineDateTime) {
            $ShutDownVMDeadlinePassed = $true
        }
        else {
            $ShutDownVMDeadlinePassed = $false
        }

        ## Handle delete VM DeadlineTime
        $DeleteVMDeadlineDataTime = [System.DateTime]::ParseExact($DeleteVMDeadline, 'yyyyMMddHHmm', $null)
        ## Set Force Logoff if at or after deadline
        if ($CurrentDateTime -ge $DeleteVMDeadlineDataTime) {
            $DeleteVMDeadlinePassed = $true
        }
        else {
            $DeleteVMDeadlinePassed = $false
        }

        # Validate and get HostPool info
        $HostPool = $null
        try {
            Write-Log "Get Hostpool info: `"$($HostPoolName)`" in resource group: `"$HostpoolRGName`"."
            $HostPool = Get-AzWvdHostPool -Name $HostPoolName -ResourceGroupName $HostpoolRGName
            if (-not $HostPool) {
                throw $HostPool
            }
        }
        catch {
            Write-Log "Hostpoolname `"$($HostpoolName)`" does not exist. Ensure that you have entered the correct values."
            exit
        }

        Write-Log "Starting WVD Hostpool Update: Current Date Time is: $CurrentDateTime"

        # Get list of session hosts in hostpool
        $SessionHosts = Get-AzWvdSessionHost -HostPoolName $HostpoolName -ResourceGroupName $HostPoolRGName -ErrorAction Stop | Sort-Object Name
        # Check if the hostpool has session hosts
        if (-not $SessionHosts) {
            Write-Log "There are no session hosts in the `"$($HostpoolName)`" Hostpool."
            exit
        }
        $SessionHostCount = $SessionHosts.Count
        Write-Log "Processing hostpool $($HostpoolName) which contains $SessionHostCount session hosts."

        # Initialize variables for tracking running old session hosts.
        $RunningOldHosts = 0
        $RunningOldHosts = @()
        [int]$NumberOfRunningHosts = 0
        $vmsToRemove = [System.Collections.ArrayList]@()

        # Analyze the SessionHosts and Azure VM instances for applicability and to determine power state. Delete any turned off VMs if DeleteVM is specified.
        Write-Log "####################"
        Write-Log "##  ANALYZE HOSTS ##"
        Write-Log "##----------------##"

        Write-Log "Fetch VMs from resource group [$HostPoolRGName]"

        try {
            $hostPoolVMs = Get-VirtualMachinePropertiesByAzGraph -ResourceGroupName $HostPoolRGName
            Write-Log "VM properties retrieved for $($hostPoolVMs.count) VMs"
        }
        catch {
            Write-Log "ERROR: Failed to retrieve VM properties or VM powerstate with error: $($_.exception.message)"
            Write-Error ($_.exception.message)
        }

        foreach ($SessionHost in $SessionHosts) {
            Write-Log "--------------------------------------------------------------------"
            $SessionHostName = $SessionHost.Name.Split("/")[1]
            $VMName = $SessionHostName.split('.')[0]
            $VMInstance = $hostPoolVMs | Where-Object { $_.name -eq $VMName }
            $VMStateProperties = Get-TableProperty -vmname $VMName -hostpoolName $HostpoolName -stateTable $stateTable

            Write-Log "[$VMName] Analyzing session host [$SessionHostName] for image version and power state."

            if (-not $VMInstance) {
                Write-Log "[$VMName] The VM connected to session host [$SessionHostName] does not exist. Unregistering it."
                Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolRGName -Name $SessionHostName
                Remove-StateTableEntry -vmname $VMName -hostpoolName $HostpoolName -stateTable $stateTable
                continue
            }

            # Check if VM has new Image or old image based on ImageVersion tag Value
            if ($VMStateProperties.Keys -notcontains $ImageVersionPropName) {
                Write-Log "[$VMName] First time VM is handled. Adding required tags to VM and skipping further actions."
                Set-TableProperty -vmname $VMName -hostpoolName $HostpoolName -propertyTuples @{ $ImageVersionPropName = $TargetImageVersion.ToString() } -stateTable $stateTable
                continue
            }
            elseif ($VMStateProperties.$ImageVersionPropName -eq $TargetImageVersion) {
                Write-Log "[$VMName] VM is based on correct image version, skipping this VM."
                continue
            }
            else {
                Write-Log "[$VMName] VM is not based on correct image version."
                Set-TableProperty -vmname $VMName -hostpoolName $HostpoolName -propertyTuples @{ $NoScalingPropName = $true } -stateTable $stateTable  # Used e.g. by the scaling script to identify machines to ignore
            }

            # Set Drain Mode if not already set
            if ($SessionHost.AllowNewSession) {
                Update-AzWvdSessionHost -Name $SessionHostName -HostPoolName $HostPoolName -ResourceGroupName $HostPoolRGName -AllowNewSession:$False | Out-Null
                Set-TableProperty -vmname $VMName -hostpoolName $HostpoolName -propertyTuples @{ $DrainModePropName = $true } -stateTable $stateTable
            }

            if ($SessionHostName.ToLower().Contains($VMInstance.name.ToLower())) {
                # Check if the Azure vm is running
                if ($VMInstance.properties.extended.instanceView.powerState.displayStatus -eq "VM running") {
                    Write-Log "[$VMName] VM is currently powered on."
                    $NumberOfRunningHosts = $NumberOfRunningHosts + 1
                    $RunningOldHosts += $SessionHost
                }
                else {
                    Write-Log "[$VMName] VM is currently powered off."
                    if ($DeleteVMDeadlinePassed) {
                        Write-Log "[$VMName] The 'DeleteVM Deadline' passed. The stopped VM is being scheduled to be deleted from resource group [$HostPoolRGName] and removed from hostpool [$HostPoolName]"
                        $null = $vmsToRemove.Add($VMInstance)
                        Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolRGName -Name $SessionHostName
                        Remove-StateTableEntry -vmname $VMName -hostpoolName $HostpoolName -stateTable $stateTable
                    }
                }
            }
        }

        Write-Log "#####################"
        Write-Log "##  PROCESS HOSTS  ##"
        Write-Log "##-----------------##"

        # Process powered on VMs to determine if there are user sessions. If no sessions, stop (or delete VM). If sessions, then send message to active sessions or forcefully logoff users if Deadline has passed.
        # Stop or Delete VM after all user sessions are removed.
        if ($NumberofRunningHosts -gt 0) {
            $SessionHost = $null
            Write-Log "Current number of running hosts that need to be stopped: $NumberOfRunningHosts"
            Write-Log "Now processing the old Running hosts."

            foreach ($SessionHost in $RunningOldHosts) {
                Write-Log "--------------------------------------------------------------------"

                $SessionHostName = $SessionHost.Name.Split("/")[1]
                $VMName = $SessionHostName.split('.')[0]
                $VMInstance = $hostPoolVMs | Where-Object { $_.name -eq $VMName }

                Write-Log "[$VMName] Processing session host [$SessionHostName]"

                if ($SessionHostName.ToLower().Contains($VMInstance.name.ToLower())) {
                    $UserSessions = Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $HostPoolRGName -SessionHostName $SessionHostName
                    $ExistingSessions = $UserSessions.Count
                    if ($ExistingSessions -gt 0) {
                        Write-Log "[$VMName] There are [$ExistingSessions] user sessions on session host [$SessionHostName]"
                        If ($ShutDownVMDeadlinePassed) {
                            Write-Log "[$VMName] Logging off all users because deadline has passed."
                            foreach ($Session in $UserSessions) {
                                $SplitSessionID = $Session.Id.Split("/")
                                $SessionID = $SplitSessionID[$SplitSessionID.Count - 1]
                                try {
                                    Remove-AzWvdUserSession -ResourceGroupName $HostPoolRGName -HostPoolName $HostpoolName -SessionHostName $SessionHostName -Id $SessionId -Force
                                    Write-Log ("[$VMName] Forcefully logged off the user [{0}]" -f ($Session.ActiveDirectoryUserName))
                                }
                                catch {
                                    Write-Log "[$VMName] Failed to log off user with error: $($_.exception.message)"
                                }
                            }

                            # Check for User Sessions every 5 seconds and wait for them to equal 0 or 30 sec timeout to expire.
                            $timer = 0
                            do {
                                $ExistingSessions = (Get-AzWvdUserSession -HostPoolName $HostpoolName -ResourceGroupName $HostPoolRGName -SessionHostName $SessionHostName).Count
                                $timer = $timer + 5
                                Start-Sleep -seconds 5
                            } until (($ExistingSessions -eq 0) -or ($timer -ge 30))

                            # Don't want to stop or delete a VM if we couldn't remove existing sessions because it could cause profile corruption or the user(s) may not be able to logon afterwards.
                            If ($ExistingSessions -eq 0) {
                                if ($DeleteVMDeadlinePassed) {
                                    Write-Log "[$VMName] The 'DeleteVM Deadline' passed. The stopped VM is being scheduled to be deleted from resource group [$HostPoolRGName] and removed from hostpool [$HostPoolName]."
                                    $null = $vmsToRemove.Add($VMInstance)
                                    Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolRGName -Name $SessionHostName
                                    Remove-StateTableEntry -vmname $VMName -hostpoolName $HostpoolName -stateTable $stateTable
                                }
                                else {
                                    # Shutdown the Azure VM
                                    Write-Log "[$VMName] There are no more active user sessions on session host [$SessionHostName], but the delete VM deadline did not yes pass. Stopping the Azure VM."
                                    Stop-SessionHost -VMName $VMName
                                }
                            }
                            else {
                                Write-Log "[$VMName] Unable to stop Azure VM: because it still has existing sessions."
                            }
                        }
                        else {
                            foreach ($Session in $UserSessions) {
                                $SplitSessionID = $Session.Id.Split("/")
                                $SessionID = $SplitSessionID[$SplitSessionID.Count - 1]
                                Write-Log ("[$VMName] User [{0}] has Session ID: [$SessionID]" -f $Session.ActiveDirectoryUserName)
                                if ($session.SessionState -eq "Active") {
                                    # Send notification
                                    try {
                                        Send-AzWvdUserSessionMessage -ResourceGroupName $HostPoolRGName -HostPoolName $HostpoolName -SessionHostName $SessionHostName -UserSessionId $SessionId -MessageTitle $LogOffMessageTitle -MessageBody "$($LogOffMessageBody) You will be logged off automatically at $($DeadlineDateTime)." -ErrorAction Stop
                                        Write-Log ("[$VMName] Sent a log off message to user [{0}]" -f ($Session.ActiveDirectoryUserName))
                                    }
                                    catch {
                                        Write-Log "[$VMName] Failed to send message to user with error: $($_.exception.message)"
                                    }
                                }
                            }
                        }
                    }
                    else {
                        if ($DeleteVMDeadlinePassed) {
                            Write-Log "[$VMName] The 'DeleteVM Deadline' passed. The stopped VM is being scheduled to be deleted from resource group [$HostPoolRGName] and removed from hostpool [$HostPoolName]"
                            $null = $vmsToRemove.Add($VMInstance)
                            Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolRGName -Name $SessionHostName
                            Remove-StateTableEntry -vmname $VMName -hostpoolName $HostpoolName -stateTable $stateTable
                        }
                        else {
                            # Shutdown the Azure VM
                            Write-Log "[$VMName] There are no more active user sessions on session host [$SessionHostName], but the delete VM deadline did not yes pass. Stopping the Azure VM."
                            Stop-SessionHost -VMName $VMName
                        }
                    }
                }
            }
        }
        else {
            Write-Log "No currently running VMs to be shut down and or removed."
        }

        if ($vmsToRemove.Count -gt 0) {

            Write-Log "################################"
            Write-Log "## HANDLE VMs SET FOR REMOVAL ##"
            Write-Log "##----------------------------##"
            Write-Log ("Processing [{0}] VMs for removal" -f $vmsToRemove.Count)

            Remove-VirtualMachineByLoop -VmsToRemove $vmsToRemove -ResourcegroupName $HostPoolRGName -UtcOffset $UtcOffset | Out-Null
        }

        Write-Log "#########################"
        Write-Log "##  SET RG-LEVEL TAGS  ##"
        Write-Log "##---------------------##"

        $rgLevelTaggingInput = @{
            HostPoolRGName           = $HostPoolRGName
            HostPoolName             = $HostPoolName
            TargetImageVersion       = $TargetImageVersion
            ShutDownVMDeadlinePassed = $ShutDownVMDeadlinePassed
            stateTable               = $stateTable
        }
        Set-ResourceGroupLifecycleTag @rgLevelTaggingInput
    }

    end {}
}