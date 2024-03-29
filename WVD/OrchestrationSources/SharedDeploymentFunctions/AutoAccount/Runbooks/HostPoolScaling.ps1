
<#
.SYNOPSIS
	v0.1.35
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(mandatory = $false)]
    [object] $WebHookData,

    # Note: optional for simulating user sessions
    [Parameter(mandatory = $false)]
    [System.Nullable[int]]$OverrideNUserSessions
)
try {
    ######################################################################################################################
    ## HELPER FUNCTIONS                                                                                                 ##
    ## ---------------------------------------------------------------------------------------------------------------- ##
    ## Set exec policies, set TLS 1.2 security protocol, log rqt params, etc.                                           ##
    ######################################################################################################################
    #region helper functions
    function Get-PSObjectPropVal {
        param (
            $Obj,
            [string]$Key,
            $Default = $null
        )
        $Prop = $Obj.PSObject.Properties[$Key]
        if ($Prop) {
            return $Prop.Value
        }
        return $Default
    }

    # Function to return local time converted from UTC
    function Get-LocalDateTime {
        return (Get-Date).ToUniversalTime().AddHours($TimeDiffHrsMin[0]).AddMinutes($TimeDiffHrsMin[1])
    }

    function Write-Log {

        # Note: this is required to support param such as ErrorAction
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [switch]$Err,

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
            Write-Output $WriteMessage
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

            $PostResult = Send-OMSAPIIngestionFile -customerId $LogAnalyticsWorkspaceId -sharedKey $LogAnalyticsPrimaryKey -Body $json_body -logType 'WVDTenantScale_CL' -TimeStampField 'TimeStamp'
            if ($PostResult -ine 'Accepted') {
                throw "Error posting to OMS: $PostResult"
            }
        }
        catch {
            Write-Warning "$MessageTimeStamp Some error occurred while logging to log analytics workspace: $($PSItem | Format-List -Force | Out-String)"
        }
    }

    function Set-nVMsToStartOrStop {
        param (
            [Parameter(Mandatory = $true)]
            [int]$nRunningVMs,

            [Parameter(Mandatory = $true)]
            [int]$nRunningCores,

            [Parameter(Mandatory = $true)]
            [int]$nUserSessions,

            [Parameter(Mandatory = $true)]
            [int]$MaxUserSessionsPerVM,

            [Parameter(Mandatory = $false)]
            [switch]$InPeakHours,

            [Parameter(Mandatory = $false)]
            [switch] $StartOnConnectEnabled,

            [Parameter(Mandatory = $true)]
            [hashtable]$Res
        )

        # check if need to adjust min num of running session hosts required if the number of user sessions is close to the max allowed by the min num of running session hosts required
        [double]$MaxUserSessionsThreshold = 0.9
        [int]$MaxUserSessionsThresholdCapacity = [math]::Floor($MinRunningVMs * $MaxUserSessionsPerVM * $MaxUserSessionsThreshold)
        if ($nUserSessions -gt $MaxUserSessionsThresholdCapacity) {
            $MinRunningVMs = [math]::Ceiling($nUserSessions / ($MaxUserSessionsPerVM * $MaxUserSessionsThreshold))
            Write-Log "Number of user sessions is more than $($MaxUserSessionsThreshold * 100) % of the max number of sessions allowed with minimum number of running session hosts required ($MaxUserSessionsThresholdCapacity). Adjusted minimum number of running session hosts required to $MinRunningVMs"
        }

        # Check if minimum number of session hosts are running
        if ($nRunningVMs -lt $MinRunningVMs) {
            $res.nVMsToStart = $MinRunningVMs - $nRunningVMs
            Write-Log "Number of running session host is less than minimum required. Need to start $($res.nVMsToStart) VMs"
        }

        if ($InPeakHours -and -not $StartOnConnectEnabled) {
            [double]$nUserSessionsPerCore = $nUserSessions / $nRunningCores
            # In peak hours: check if current capacity is meeting the user demands
            if ($nUserSessionsPerCore -gt $UserSessionThresholdPerCore) {
                $res.nCoresToStart = [math]::Ceiling(($nUserSessions / $UserSessionThresholdPerCore) - $nRunningCores)
                Write-Log "[In peak hours] Number of user sessions per Core is more than the threshold. Need to start $($res.nCoresToStart) cores"
            }

            return
        }

        if ($nRunningVMs -gt $MinRunningVMs) {
            # Calculate the number of session hosts to stop
            $res.nVMsToStop = $nRunningVMs - $MinRunningVMs
            Write-Log "[Off peak hours] Number of running session host is greater than minimum required. Need to stop $($res.nVMsToStop) VMs"
        }
    }

    # Function to wait for background jobs
    function Wait-ForJobs {
        param ([array]$Jobs = @())

        Write-Log "Wait for $($Jobs.Count) jobs"
        $StartTime = Get-Date
        [string]$StatusInfo = ''
        while ($true) {
            if ((Get-Date).Subtract($StartTime).TotalSeconds -ge $StatusCheckTimeOut) {
                throw "Jobs status check timed out. Taking more than $StatusCheckTimeOut seconds. $StatusInfo"
            }
            $StatusInfo = "[Check jobs status] Total: $($Jobs.Count), $(($Jobs | Group-Object State | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', ')"
            Write-Log $StatusInfo
            if (-not ($Jobs | Where-Object { $_.State -ieq 'Running' })) {
                break
            }
            Start-Sleep -Seconds 30
        }

        [array]$IncompleteJobs = @($Jobs | Where-Object { $_.State -ine 'Completed' })
        if ($IncompleteJobs) {
            throw "$($IncompleteJobs.Count)/$($Jobs.Count) jobs did not complete successfully: $($IncompleteJobs | Format-List -Force | Out-String)"
        }
    }

    function Get-SessionHostName {
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            $SessionHost
        )
        return $SessionHost.Name.Split('/')[-1]
    }

    function Update-SessionHostDrainMode {
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [hashtable]$VM,

            [switch]$AllowNewSession
        )
        Begin { }
        Process {
            $SessionHost = $VM.SessionHost
            if ($SessionHost.AllowNewSession -eq $AllowNewSession) {
                return
            }

            [string]$SessionHostName = $VM.SessionHostName
            Write-Log "Update session host '$SessionHostName' to set allow new sessions to $AllowNewSession"
            if ($PSCmdlet.ShouldProcess($SessionHostName, "Update session host to set allow new sessions to $AllowNewSession")) {
                try {
                    $SessionHost = $VM.SessionHost = Update-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -Name $SessionHostName -AllowNewSession:$AllowNewSession
                    if ($SessionHost.AllowNewSession -ne $AllowNewSession) {
                        throw $SessionHost
                    }
                }
                catch {
                    Write-Log -Warn "Failed to update the session host '$SessionHostName' to set allow new sessions to $($AllowNewSession): $($PSItem | Format-List -Force | Out-String)"
                }
            }
        }
        End { }
    }

    function Disconnect-UserByForce {
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            $Session
        )
        Begin { }
        Process {
            [string[]]$Toks = $Session.Name.Split('/')
            [string]$SessionHostName = $Toks[1]
            [string]$SessionID = $Toks[-1]
            try {
                Write-Log "Force log off user: '$($Session.ActiveDirectoryUserName)', session ID: $SessionID"
                if ($PSCmdlet.ShouldProcess($SessionID, 'Force log off user with session ID')) {
                    Remove-AzWvdUserSession -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -SessionHostName $SessionHostName -Id $SessionID -Force
                }
            }
            catch {
                Write-Log -Warn "Failed to force log off user: '$($Session.ActiveDirectoryUserName)', session ID: $SessionID $($PSItem | Format-List -Force | Out-String)"
            }
        }
        End { }
    }

    function Reset-SessionHostDrainModeAndUserSession {
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [hashtable]$VM
        )
        Begin { }
        Process {
            Update-SessionHostDrainMode -VM $VM -AllowNewSession:$true

            $SessionHost = $VM.SessionHost
            [string]$SessionHostName = $VM.SessionHostName
            if (-not $SessionHost.Session) {
                return
            }

            Write-Log -Warn "Session host '$SessionHostName' still has $($SessionHost.Session) sessions left behind in broker DB"

            [array]$UserSessions = @()
            Write-Log "Get all user sessions from session host '$SessionHostName'"
            try {
                $UserSessions = @(Get-AzWvdUserSession -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -SessionHostName $SessionHostName)
            }
            catch {
                Write-Log -Warn "Failed to retrieve user sessions of session host '$SessionHostName': $($PSItem | Format-List -Force | Out-String)"
                return
            }

            Write-Log "Force log off $($UserSessions.Count) users on session host: '$SessionHostName'"
            $UserSessions | Disconnect-UserByForce
        }
        End { }
    }

    function Get-TableProperty {

        <#
        .SYNOPSIS
        Get the value of the given property from the state table

        .DESCRIPTION
        Get the value of the given property from the state table

        .PARAMETER vmName
        The VM entry to fetch. Acts as the row identifier

        .PARAMETER hostpoolName
        The name of the host pool. Used as a partition key

        .PARAMETER property
        Mandatory. The property to fetch (e.g. version). Correspondings to the table column

        .PARAMETER stateTable
        Mandatory. The storage table to fetch the data from. Can be fetched via `$stateTable = Get-AzStorageTable –Name $stateTableName –Context $sa.Context`

        .EXAMPLE
        Get-TableProperty -vmname 'vm01' -hostpoolName 'hp' -property 'version'-stateTable (Get-AzStorageTable –Name 'hostpool01Table' –Context (Get-AzStorageAccount -Name 'stateSa' -ResourceGroup 'stateSaRg').Context)

        Get the value of the property 'version' of the row with key 'vm01' and partition 'hp' in the storage account 'stateSa' table 'hostpool01Table'

        .EXAMPLE
        Get-TableProperty -vmname 'vm01' -hostpoolName 'hp'-stateTable (Get-AzStorageTable –Name 'hostpool01Table' –Context (Get-AzStorageAccount -Name 'stateSa' -ResourceGroup 'stateSaRg').Context)

        Get the all properties of the row with key 'vm01' and partition 'hp' in the storage account 'stateSa' table 'hostpool01Table'
        #>
        [CmdletBinding()]
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [string] $vmName,

            [Parameter(Mandatory = $true)]
            [string] $hostpoolName,

            [Parameter(Mandatory = $false)]
            [string] $property = '',

            [Parameter(Mandatory = $true)]
            [object] $stateTable
        )

        if ($row = Get-AzStorageTableRowByPartitionKeyRowKey -table $stateTable -partitionKey $hostpoolName -rowKey $vmName -ErrorAction 'SilentlyContinue') {
            if ([string]::IsNullOrEmpty($property)) {
                $propertiesTable = @{}
                $row.psobject.properties | ForEach-Object { $propertiesTable[$_.Name] = $_.Value }
                return $propertiesTable
            }
            else {
                return $row.$property
            }
        }
        else {
            return ''
        }
    }
    #endregion

    ######################################################################################################################
    ## PREPARATION                                                                                                      ##
    ## ---------------------------------------------------------------------------------------------------------------- ##
    ## Set err action preference, extract & validate input rqt params                                                   ##
    ######################################################################################################################
    #region preparation
    [version]$Version = '0.1.35'

    # Setting ErrorActionPreference to stop script execution when error occurs
    $ErrorActionPreference = 'Stop'
    # Note: this is to force cast in case it's not of the desired type. Specifying this type inside before the param inside param () doesn't work because it still accepts other types and doesn't cast it to this type
    $WebHookData = [PSCustomObject]$WebHookData

    # If runbook was called from Webhook, WebhookData and its RequestBody will not be null
    if (-not $WebHookData -or [string]::IsNullOrWhiteSpace((Get-PSObjectPropVal -Obj $WebHookData -Key 'RequestBody'))) {
        throw 'Runbook was not started from Webhook (WebHookData or its RequestBody is empty)'
    }

    # Collect Input converted from JSON request body of Webhook
    $ScalingInput = ConvertFrom-Json -InputObject $WebHookData.RequestBody

    if (-not $ScalingInput) {
        throw 'RequestBody of WebHookData is empty'
    }

    [string[]]$RequiredStrParams = @(
        'ResourceGroupName'
        'HostPoolName'
        'UtcOffset'
        'BeginPeakTime'
        'EndPeakTime'
    )
    if (Get-PSObjectPropVal -Obj $ScalingInput -Key 'LimitSecondsToForceLogOffUser') {
        $RequiredStrParams += @('LogOffMessageTitle', 'LogOffMessageBody')
    }
    [string[]]$RequiredParams = @('SessionThresholdPerCPU', 'MinimumNumberOfRDSH', 'LimitSecondsToForceLogOffUser')
    [string[]]$InvalidParams = @($RequiredStrParams | Where-Object { [string]::IsNullOrWhiteSpace((Get-PSObjectPropVal -Obj $ScalingInput -Key $_)) })
    [string[]]$InvalidParams += @($RequiredParams | Where-Object { $null -eq (Get-PSObjectPropVal -Obj $ScalingInput -Key $_) })

    if ($InvalidParams) {
        throw "Invalid values for the following $($InvalidParams.Count) params: $($InvalidParams -join ', ')"
    }

    [string]$LAWorkspaceName = $ScalingInput.LAWorkspaceName
    [string]$ConnectionAssetName = Get-PSObjectPropVal -Obj $ScalingInput -Key 'ConnectionAssetName'
    [string]$ResourceGroupName = $ScalingInput.ResourceGroupName
    [string]$HostPoolName = $ScalingInput.HostPoolName
    [string]$MaintenanceTagName = Get-PSObjectPropVal -Obj $ScalingInput -Key 'MaintenanceTagName'
    [string]$UtcOffset = $ScalingInput.UtcOffset
    [string]$BeginPeakTime = $ScalingInput.BeginPeakTime
    [string]$EndPeakTime = $ScalingInput.EndPeakTime
    [string]$stateStorageAccountName = $ScalingInput.stateStorageAccountName
    [string]$stateTableName = $ScalingInput.stateTableName
    [double]$UserSessionThresholdPerCore = $ScalingInput.SessionThresholdPerCPU
    [int]$MinRunningVMs = $ScalingInput.MinimumNumberOfRDSH
    [int]$LimitSecondsToForceLogOffUser = $ScalingInput.LimitSecondsToForceLogOffUser
    [string]$LogOffMessageTitle = Get-PSObjectPropVal -Obj $ScalingInput -Key 'LogOffMessageTitle'
    [string]$LogOffMessageBody = Get-PSObjectPropVal -Obj $ScalingInput -Key 'LogOffMessageBody'

    # Note: if this is enabled, the script will assume that all the authentication is already done in current or parent scope before calling this script
    [bool]$SkipAuth = !!(Get-PSObjectPropVal -Obj $ScalingInput -Key 'SkipAuth')
    [bool]$SkipUpdateLoadBalancerType = !!(Get-PSObjectPropVal -Obj $ScalingInput -Key 'SkipUpdateLoadBalancerType')

    if ([string]::IsNullOrWhiteSpace($ConnectionAssetName)) {
        $ConnectionAssetName = 'AzureRunAsConnection'
    }

    $MaintenanceTags = $($MaintenanceTagName)
    if ($MaintenanceTagName -like "*;*") {
        $MaintenanceTags = $MaintenanceTagName.Split(';')
    }

    [int]$StatusCheckTimeOut = Get-PSObjectPropVal -Obj $ScalingInput -Key 'StatusCheckTimeOut' -Default (60 * 60) # 1 hr
    # [int]$SessionHostStatusCheckSleepSecs = 30
    [string[]]$DesiredRunningStates = @('Available', 'NeedsAssistance')
    # Note: time diff can be '#' or '#:#', so it is appended with ':0' in case its just '#' and so the result will have at least 2 items (hrs and min)
    [string[]]$TimeDiffHrsMin = "$($UtcOffset):0".Split(':')

    Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -Confirm:$false

    if (-not $SkipAuth) {
        # Note: this requires admin priviledges
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$false
    }

    # Note: https://stackoverflow.com/questions/41674518/powershell-setting-security-protocol-to-tls-1-2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "Request params: $($ScalingInput | Format-List -Force | Out-String)"

    #endregion

    ######################################################################################################################
    ## AUTHENTICATION                                                                                                   ##
    ######################################################################################################################
    #region authentication
    if (-not $SkipAuth) {
        # Collect the credentials from Azure Automation Account Assets
        Write-Log "Get auto connection from asset: '$ConnectionAssetName'"
        $ConnectionAsset = Get-AutomationConnection -Name $ConnectionAssetName

        # Azure auth
        $AzContext = $null
        try {
            $AzAuth = Connect-AzAccount -ApplicationId $ConnectionAsset.ApplicationId -CertificateThumbprint $ConnectionAsset.CertificateThumbprint -TenantId $ConnectionAsset.TenantId -SubscriptionId $ConnectionAsset.SubscriptionId -ServicePrincipal
            if (-not $AzAuth -or !$AzAuth.Context) {
                throw $AzAuth
            }
            $AzContext = $AzAuth.Context
        }
        catch {
            throw [System.Exception]::new('Failed to authenticate Azure with application ID, tenant ID, subscription ID', $PSItem.Exception)
        }
        Write-Log "Successfully authenticated with Azure using service principal: $($AzContext | Format-List -Force | Out-String)"

        # Set Azure context with subscription, tenant
        if ($AzContext.Tenant.Id -ine $ConnectionAsset.TenantId -or $AzContext.Subscription.Id -ine $ConnectionAsset.SubscriptionId) {
            if ($PSCmdlet.ShouldProcess((@($ConnectionAsset.TenantId, $ConnectionAsset.SubscriptionId) -join ', '), 'Set Azure context with tenant ID, subscription ID')) {
                try {
                    $AzContext = Set-AzContext -TenantId $ConnectionAsset.TenantId -SubscriptionId $ConnectionAsset.SubscriptionId
                    if (-not $AzContext -or $AzContext.Tenant.Id -ine $ConnectionAsset.TenantId -or $AzContext.Subscription.Id -ine $ConnectionAsset.SubscriptionId) {
                        throw $AzContext
                    }
                }
                catch {
                    throw [System.Exception]::new('Failed to set Azure context with tenant ID, subscription ID', $PSItem.Exception)
                }
                Write-Log "Successfully set the Azure context with the tenant ID, subscription ID: $($AzContext | Format-List -Force | Out-String)"
            }
        }
    }


    ## Storage Table
    ## -------------
    if (-not ([String]::IsNullOrEmpty($stateStorageAccountName))) {
        $stateStorageAccountResource = Get-AzResource -Name $stateStorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts'
        $stateStorageAccount = Get-AzStorageAccount -Name $stateStorageAccountName -ResourceGroupName $stateStorageAccountResource.ResourceGroupName
        $stateTable = Get-AzStorageTable –Name $stateTableName –Context $stateStorageAccount.Context
        ### PropertyNames
        $NoScalingPropName = 'NoScaling'
    }

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

    #endregion

    ######################################################################################################################
    ## VALIDATE HOST POOL                                                                                               ##
    ## ---------------------------------------------------------------------------------------------------------------- ##
    ## Validate / update HostPool load balancer type, ensure there is at least 1 session host, get num of user sessions ##
    ######################################################################################################################
    #region Validate host pool
    $deployments = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -ErrorAction 'SilentlyContinue'
    if ($deployments) {
        if (($deployments | Where-Object { $_.ProvisioningState -eq 'Running' }).Count -gt 0) {
            Write-Log "Still deploying resources to resource group [$ResourceGroupName]. Exclude from scaling."
            return
        }
    }

    # Validate and get HostPool info
    $HostPool = $null
    try {
        Write-Log "Get Hostpool info of '$HostPoolName' in resource group '$ResourceGroupName'"
        $HostPool = Get-AzWvdHostPool -ResourceGroupName $ResourceGroupName -Name $HostPoolName
        if (-not $HostPool) {
            throw 'No Host pool [$hostpoolName] deployed into resource group [$ResourceGroupName]'
        }
    }
    catch {
        throw [System.Exception]::new("Failed to get Hostpool info of '$HostPoolName' in resource group '$ResourceGroupName'. Ensure that you have entered the correct values", $PSItem.Exception)
    }

    # Ensure HostPool load balancer type is not persistent
    if ($HostPool.LoadBalancerType -ieq 'Persistent') {
        throw "HostPool '$HostPoolName' is configured with 'Persistent' load balancer type. Scaling tool only supports these load balancer types: BreadthFirst, DepthFirst"
    }

    Write-Log 'Get all session hosts'
    $SessionHosts = @(Get-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName)
    if (-not $SessionHosts) {
        Write-Log "There are no session hosts in the Hostpool '$HostPoolName'. Ensure that hostpool has session hosts"
        Write-Log 'End'
        return
    }

    Write-Log 'Get number of user sessions in Hostpool'
    [int]$nUserSessions = @(Get-AzWvdUserSession -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName).Count

    # Set up breadth 1st load balacing type
    # Note: breadth 1st is enforced on AND off peak hours to simplify the things with scaling in the start/end of peak hours
    if (-not $SkipUpdateLoadBalancerType -and $HostPool.LoadBalancerType -ine 'BreadthFirst') {
        Write-Log "Update HostPool with 'BreadthFirst' load balancer type (current: '$($HostPool.LoadBalancerType)')"
        if ($PSCmdlet.ShouldProcess($HostPoolName, "Update HostPool with BreadthFirstLoadBalancer type (current: '$($HostPool.LoadBalancerType)')")) {
            $HostPool = Update-AzWvdHostPool -ResourceGroupName $ResourceGroupName -Name $HostPoolName -LoadBalancerType 'BreadthFirst'
        }
    }

    Write-Log "HostPool info: $($HostPool | Format-List -Force | Out-String)"
    Write-Log "Number of session hosts in the HostPool: $($SessionHosts.Count)"
    #endregion

    ######################################################################################################################
    ## DETERMINE PEAK/OFF-PEAK HOURS                                                                                    ##
    ######################################################################################################################
    #region workhours
    # Convert local time, begin peak time & end peak time from UTC to local time
    $CurrentDateTime = Get-LocalDateTime
    $BeginPeakDateTime = [datetime]::Parse($CurrentDateTime.ToShortDateString() + ' ' + $BeginPeakTime)
    $EndPeakDateTime = [datetime]::Parse($CurrentDateTime.ToShortDateString() + ' ' + $EndPeakTime)

    # Adjust peak times to make sure begin peak time is always before end peak time
    if ($EndPeakDateTime -lt $BeginPeakDateTime) {
        if ($CurrentDateTime -lt $EndPeakDateTime) {
            $BeginPeakDateTime = $BeginPeakDateTime.AddDays(-1)
        }
        else {
            $EndPeakDateTime = $EndPeakDateTime.AddDays(1)
        }
    }

    Write-Log "Using current time: $($CurrentDateTime.ToString('yyyy-MM-dd HH:mm:ss')), begin peak time: $($BeginPeakDateTime.ToString('yyyy-MM-dd HH:mm:ss')), end peak time: $($EndPeakDateTime.ToString('yyyy-MM-dd HH:mm:ss'))"

    [bool]$InPeakHours = ($BeginPeakDateTime -le $CurrentDateTime -and $CurrentDateTime -le $EndPeakDateTime)
    if ($InPeakHours) {
        Write-Log 'In peak hours'
    }
    else {
        Write-Log 'Off peak hours'
    }
    #endregion

    ######################################################################################################################
    ## COLLECT HOST-POOL DATA                                                                                           ##
    ## ---------------------------------------------------------------------------------------------------------------- ##
    ## All session hosts, VMs, User Sessions and workloads                                                              ##
    ######################################################################################################################
    #region  hostpooldata

    # Note: session host is considered "running" if its running AND is in desired states AND allowing new sessions
    # Number of session hosts that are running, are in desired states and allowing new sessions
    [int]$nRunningVMs = 0
    # Number of cores that are running, are in desired states and allowing new sessions
    [int]$nRunningCores = 0
    # Object that contains all session host objects, VM instance objects except the ones that are under maintenance
    $VMs = @{ }
    # Object that contains the number of cores for each VM size SKU
    $VMSizeCores = @{ }
    # Number of user sessions reported by each session host that is running, is in desired state and allowing new sessions
    [int]$nUserSessionsFromAllRunningVMs = 0

    # Popoluate all session hosts objects
    foreach ($SessionHost in $SessionHosts) {
        [string]$SessionHostName = (Get-SessionHostName -SessionHost $SessionHost).ToLower()
        $VMs.Add($SessionHostName.Split('.')[0], @{ 'SessionHostName' = $SessionHostName; 'SessionHost' = $SessionHost; 'Instance' = $null })
    }

    Write-Log 'Get all VMs, check session host status and get usage info'
    foreach ($VMInstance in (Get-AzVM -Status -ResourceGroupName $ResourceGroupName)) {
        if (-not $VMs.ContainsKey($VMInstance.Name.ToLower())) {
            # This VM is not a WVD session host
            continue
        }

        ### HANDLE EXCLUDE TAGS / EXCLUDE STATE
        [string]$VMName = $VMInstance.Name.ToLower()
        if (-not [String]::IsNullOrEmpty($stateTable)) {
            $skipByStateTable = (Get-TableProperty -vmname $VMName -hostpoolName $HostPoolName -stateTable $stateTable -property $NoScalingPropName) -eq $true
        }
        $skipByTag = (Compare-Object -ReferenceObject ([string[]] $VMInstance.Tags.Keys) -DifferenceObject $MaintenanceTags -IncludeEqual -ExcludeDifferent).Count -gt 0
        if ($skipByStateTable -or $skipByTag) {
            Write-Log ("VM [$VMName] is in configured to be excluded from Scaling and will be ignored")
            $VMs.Remove($VMName)
            continue
        }
        ####

        $VM = $VMs[$VMName]
        $SessionHost = $VM.SessionHost
        if ($VM.Instance) {
            throw "More than 1 VM found in Azure with same session host name '$($VM.SessionHostName)' (This is not supported): $($VMInstance | Format-List -Force | Out-String)$($VM.Instance | Format-List -Force | Out-String)"
        }

        $VM.Instance = $VMInstance

        Write-Log "Session host: '$($VM.SessionHostName)', power state: '$($VMInstance.PowerState)', status: '$($SessionHost.Status)', update state: '$($SessionHost.UpdateState)', sessions: $($SessionHost.Session), allow new session: $($SessionHost.AllowNewSession)"
        # Check if we know how many cores are in this VM
        if (-not $VMSizeCores.ContainsKey($VMInstance.HardwareProfile.VmSize)) {
            Write-Log "Get all VM sizes in location: $($VMInstance.Location)"
            foreach ($VMSize in (Get-AzVMSize -Location $VMInstance.Location)) {
                $VMSizeCores.Add($VMSize.Name, $VMSize.NumberOfCores)
            }
        }

        if ($VMInstance.PowerState -ieq 'VM running') {
            if ($SessionHost.Status -notin $DesiredRunningStates) {
                Write-Log -Warn 'VM is in running state but session host is not and so it will be ignored (this could be because the VM was just started and has not connected to broker yet)'
            }
            if (-not $SessionHost.AllowNewSession) {
                Write-Log -Warn 'VM is in running state but session host is not allowing new sessions and so it will be ignored'
            }

            if ($SessionHost.Status -in $DesiredRunningStates -and $SessionHost.AllowNewSession) {
                ++$nRunningVMs
                $nRunningCores += $VMSizeCores[$VMInstance.HardwareProfile.VmSize]
                $nUserSessionsFromAllRunningVMs += $SessionHost.Session
            }
        }
        else {
            if ($SessionHost.Status -in $DesiredRunningStates) {
                Write-Log -Warn "VM is not in running state but session host is (this could be because the VM was just stopped and broker doesn't know that yet)"
            }
        }
    }

    if ($nUserSessionsFromAllRunningVMs -ne $nUserSessions) {
        Write-Log -Warn "Sum of user sessions reported by every running session host ($nUserSessionsFromAllRunningVMs) is not equal to the total number of user sessions reported by the host pool ($nUserSessions)"
    }

    $nUserSessions = $nUserSessionsFromAllRunningVMs
    # Check if we need to override the number of user sessions for simulation / testing purpose
    if ($null -ne $OverrideNUserSessions) {
        $nUserSessions = $OverrideNUserSessions
    }

    # Make sure VM instance was found in Azure for every session host
    [int]$nVMsWithoutInstance = @($VMs.Values | Where-Object { !$_.Instance }).Count
    if ($nVMsWithoutInstance) {
        throw "There are $nVMsWithoutInstance/$($VMs.Count) session hosts whose VM instance was not found in Azure"
    }

    if (-not $nRunningCores) {
        $nRunningCores = 1
    }

    Write-Log "Number of running session hosts: $nRunningVMs of total $($VMs.Count)"
    Write-Log "Number of user sessions: $nUserSessions of total allowed $($nRunningVMs * $HostPool.MaxSessionLimit)"
    Write-Log "Number of user sessions per Core: $($nUserSessions / $nRunningCores), threshold: $UserSessionThresholdPerCore"
    Write-Log "Minimum number of running session hosts required: $MinRunningVMs"

    # Check if minimum num of running session hosts required is higher than max allowed
    if ($VMs.Count -le $MinRunningVMs) {
        Write-Log -Warn 'Minimum number of RDSH is set higher than or equal to total number of session hosts'
    }
    #endregion


    ######################################################################################################################
    ## CALCULATIONS                                                                                                     ##
    ## ---------------------------------------------------------------------------------------------------------------- ##
    ## Determine number of session hosts to start/stop                                                                  ##
    ######################################################################################################################
    #region calculations

    # Now that we have all the info about the session hosts & their usage, figure how many session hosts to start/stop depending on in/off peak hours and the demand [Ops = operations to perform]
    $Ops = @{
        nVMsToStart   = 0
        nCoresToStart = 0
        nVMsToStop    = 0
    }

    Set-nVMsToStartOrStop -nRunningVMs $nRunningVMs -nRunningCores $nRunningCores -nUserSessions $nUserSessions -MaxUserSessionsPerVM $HostPool.MaxSessionLimit -InPeakHours:$InPeakHours -StartOnConnectEnabled:$HostPool.StartVMOnConnect -Res $Ops
    #endregion

    ######################################################################################################################
    ## START ANY SESSION HOSTS IF REQUIRED                                                                              ##
    ######################################################################################################################
    #region startSessionHosts

    # Check if we have any session hosts to start
    if ($Ops.nVMsToStart -or $Ops.nCoresToStart) {

        if ($nRunningVMs -eq $VMs.Count) {
            Write-Log 'All session hosts are running'
            Write-Log 'End'
            return
        }

        # Object that contains names of session hosts that will be started
        # $StartSessionHostFullNames = @{ }
        # Array that contains jobs of starting the session hosts
        [array]$StartVMjobs = @()

        Write-Log 'Find session hosts that are stopped and allowing new sessions'
        foreach ($VM in $VMs.Values) {
            if (-not $Ops.nVMsToStart -and !$Ops.nCoresToStart) {
                # Done with starting session hosts that needed to be
                break
            }
            if ($VM.Instance.PowerState -ieq 'VM running') {
                continue
            }
            if ($VM.SessionHost.UpdateState -ine 'Succeeded') {
                Write-Log -Warn "Session host '$($VM.SessionHostName)' may not be healthy"
            }

            [string]$SessionHostName = $VM.SessionHostName

            if (-not $VM.SessionHost.AllowNewSession) {
                Write-Log -Warn "Session host '$SessionHostName' is not allowing new sessions and so it will not be started"
                continue
            }

            Write-Log "Start session host '$SessionHostName' as a background job"
            if ($PSCmdlet.ShouldProcess($SessionHostName, 'Start session host as a background job')) {
                # $StartSessionHostFullNames.Add($VM.SessionHost.Name, $null)
                $StartVMjobs += ($VM.Instance | Start-AzVM -AsJob)
            }

            --$Ops.nVMsToStart
            if ($Ops.nVMsToStart -lt 0) {
                $Ops.nVMsToStart = 0
            }
            $Ops.nCoresToStart -= $VMSizeCores[$VM.Instance.HardwareProfile.VmSize]
            if ($Ops.nCoresToStart -lt 0) {
                $Ops.nCoresToStart = 0
            }
        }

        # Check if there were enough number of session hosts to start
        if ($Ops.nVMsToStart -or $Ops.nCoresToStart) {
            Write-Log -Warn "Not enough session hosts to start. Still need to start maximum of either $($Ops.nVMsToStart) VMs or $($Ops.nCoresToStart) cores"
        }

        # Wait for those jobs to start the session hosts
        Wait-ForJobs $StartVMjobs

        Write-Log 'All jobs completed'
        Write-Log 'End'
        return
    }
    #endregion

    ######################################################################################################################
    ## STOP ANY SESSION HOSTS IF REQUIRED                                                                               ##
    ######################################################################################################################
    #region stopSessionHosts

    if (-not $Ops.nVMsToStop) {
        Write-Log 'No need to start/stop any session hosts'
        Write-Log 'End'
        return
    }

    [array]$StopVMjobs = @()
    $VMsToStop = @{ }
    [array]$VMsToStopAfterLogOffTimeOut = @()

    Write-Log 'Find session hosts that are running and allowing new sessions, sort them by number of user sessions'
    foreach ($VM in ($VMs.Values | Where-Object { $_.Instance.PowerState -ieq 'VM running' -and $_.SessionHost.AllowNewSession } | Sort-Object { $_.SessionHost.Session })) {
        if (-not $Ops.nVMsToStop) {
            # Done with stopping session hosts that needed to be
            break
        }
        $SessionHost = $VM.SessionHost
        [string]$SessionHostName = $VM.SessionHostName

        if ($SessionHost.Session -and !$LimitSecondsToForceLogOffUser) {
            Write-Log -Warn "Session host '$SessionHostName' has $($SessionHost.Session) sessions but limit seconds to force log off user is set to 0, so will not stop any more session hosts (https://aka.ms/wvdscale#how-the-scaling-tool-works)"
            # Break because the list this loop iterates through is sorted by number of sessions, if it hits this, the rest of items in the loop will also hit this
            break
        }

        Update-SessionHostDrainMode -VM $VM -AllowNewSession:$false
        $SessionHost = $VM.SessionHost

        # Note: check if there were new user sessions since session host info was 1st fetched
        if ($SessionHost.Session -and !$LimitSecondsToForceLogOffUser) {
            Write-Log -Warn "Session host '$SessionHostName' has $($SessionHost.Session) sessions but limit seconds to force log off user is set to 0, so will not stop any more session hosts (https://aka.ms/wvdscale#how-the-scaling-tool-works)"
            Update-SessionHostDrainMode -VM $VM -AllowNewSession:$true
            $SessionHost = $VM.SessionHost
            continue
        }

        if ($SessionHost.Session) {
            [array]$VM.UserSessions = @()
            Write-Log "Get all user sessions from session host '$SessionHostName'"
            try {
                $VM.UserSessions = @(Get-AzWvdUserSession -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -SessionHostName $SessionHostName)
            }
            catch {
                Write-Log -Warn "Failed to retrieve user sessions of session host '$SessionHostName': $($PSItem | Format-List -Force | Out-String)"
            }

            Write-Log "Send log off message to active user sessions on session host: '$SessionHostName'"
            foreach ($Session in $VM.UserSessions) {
                if ($Session.SessionState -ine 'Active') {
                    continue
                }
                [string]$SessionID = $Session.Name.Split('/')[-1]
                try {
                    Write-Log "Send a log off message to user: '$($Session.ActiveDirectoryUserName)', session ID: $SessionID"
                    if ($PSCmdlet.ShouldProcess($SessionID, 'Send a log off message to user with session ID')) {
                        Send-AzWvdUserSessionMessage -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -SessionHostName $SessionHostName -UserSessionId $SessionID -MessageTitle $LogOffMessageTitle -MessageBody "$LogOffMessageBody You will be logged off in $LimitSecondsToForceLogOffUser seconds"
                    }
                }
                catch {
                    Write-Log -Warn "Failed to send a log off message to user: '$($Session.ActiveDirectoryUserName)', session ID: $SessionID $($PSItem | Format-List -Force | Out-String)"
                }
            }
            $VMsToStopAfterLogOffTimeOut += $VM
        }
        else {
            Write-Log "Stop session host '$SessionHostName' as a background job"
            if ($PSCmdlet.ShouldProcess($SessionHostName, 'Stop session host as a background job')) {
                $StopVMjobs += ($VM.StopJob = $VM.Instance | Stop-AzVM -Force -AsJob)
                $VMsToStop.Add($SessionHostName, $VM)
            }
        }

        --$Ops.nVMsToStop
        if ($Ops.nVMsToStop -lt 0) {
            $Ops.nVMsToStop = 0
        }
    }

    if ($VMsToStopAfterLogOffTimeOut) {
        Write-Log "Wait $LimitSecondsToForceLogOffUser seconds for users to log off"
        if ($PSCmdlet.ShouldProcess("for $LimitSecondsToForceLogOffUser seconds", 'Wait for users to log off')) {
            Start-Sleep -Seconds $LimitSecondsToForceLogOffUser
        }

        Write-Log "Force log off users and stop remaining $($VMsToStopAfterLogOffTimeOut.Count) session hosts"
        foreach ($VM in $VMsToStopAfterLogOffTimeOut) {
            [string]$SessionHostName = $VM.SessionHostName

            Write-Log "Force log off $($VM.UserSessions.Count) users on session host: '$SessionHostName'"
            $VM.UserSessions | Disconnect-UserByForce

            Write-Log "Stop session host '$SessionHostName' as a background job"
            if ($PSCmdlet.ShouldProcess($SessionHostName, 'Stop session host as a background job')) {
                # $StopSessionHostFullNames.Add($VM.SessionHost.Name, $null)
                $StopVMjobs += ($VM.StopJob = $VM.Instance | Stop-AzVM -Force -AsJob)
                $VMsToStop.Add($SessionHostName, $VM)
            }
        }
    }

    # Check if there were enough number of session hosts to stop
    if ($Ops.nVMsToStop) {
        Write-Log -Warn "Not enough session hosts to stop. Still need to stop $($Ops.nVMsToStop) VMs"
    }

    # Wait for those jobs to stop the session hosts
    Write-Log "Wait for $($StopVMjobs.Count) jobs"
    $StartTime = Get-Date
    while ($true) {
        if ((Get-Date).Subtract($StartTime).TotalSeconds -ge $StatusCheckTimeOut) {
            break
        }
        if (-not ($StopVMjobs | Where-Object { $_.State -ieq 'Running' })) {
            break
        }

        Write-Log "[Check jobs status] Total: $($StopVMjobs.Count), $(($StopVMjobs | Group-Object State | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', ')"

        $VMstoResetDrainModeAndSessions = @($VMsToStop.Values | Where-Object { $_.StopJob.State -ine 'Running' })
        foreach ($VM in $VMstoResetDrainModeAndSessions) {
            Reset-SessionHostDrainModeAndUserSession -VM $VM
            $VMsToStop.Remove($VM.SessionHostName)
        }
        if (-not $VMstoResetDrainModeAndSessions) {
            Start-Sleep -Seconds 30
        }
    }

    [string]$StopVMJobsStatusInfo = "[Check jobs status] Total: $($StopVMjobs.Count), $(($StopVMjobs | Group-Object State | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', ')"
    Write-Log $StopVMJobsStatusInfo

    $VMsToStop.Values | Reset-SessionHostDrainModeAndUserSession

    if ((Get-Date).Subtract($StartTime).TotalSeconds -ge $StatusCheckTimeOut) {
        throw "Jobs status check timed out. Taking more than $StatusCheckTimeOut seconds. $StopVMJobsStatusInfo"
    }

    [array]$IncompleteJobs = @($StopVMjobs | Where-Object { $_.State -ine 'Completed' })
    if ($IncompleteJobs) {
        throw "$($IncompleteJobs.Count)/$($StopVMjobs.Count) jobs did not complete successfully: $($IncompleteJobs | Format-List -Force | Out-String)"
    }

    Write-Log 'All jobs completed'
    Write-Log 'End'
    return
    #endregion
}
catch {
    $ErrContainer = $PSItem

    [string]$ErrMsg = $ErrContainer | Format-List -Force | Out-String
    $ErrMsg += "Version: $Version`n"

    if (Get-Command 'Write-Log' -ErrorAction:SilentlyContinue) {
        Write-Log -Err -Message $ErrMsg -ErrorAction:Continue
    }
    else {
        Write-Error -Message $ErrMsg -ErrorAction:Continue
    }

    throw [System.Exception]::new($ErrMsg, $ErrContainer.Exception)
}