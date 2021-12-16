[CmdletBinding(SupportsShouldProcess = $true)]
param (

    [Parameter(Mandatory = $false)]
    [Hashtable] $DynParameters,
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigurationFileName = "fslogix.parameters.json"
)

#####################################

##########
# Helper #
##########
#region Functions
function LogInfo($message) {
    Log "Info" $message
}

function LogError($message) {
    Log "Error" $message
}

function LogSkip($message) {
    Log "Skip" $message
}

function LogWarning($message) {
    Log "Warning" $message
}

function Log {

    <#
    .SYNOPSIS
    Creates a log file and stores logs based on categories with tab seperation

    .PARAMETER category
    Category to put into the trace

    .PARAMETER message
    Message to be loged

    .EXAMPLE
    Log 'Info' 'Message'

    #>

    Param (
        $category = 'Info',
        [Parameter(Mandatory)]
        $message
    )

    $date = get-date
    $content = "[$date]`t$category`t`t$message`n"
    Write-Verbose "$content" -verbose

    if (! $script:Log) {
        $File = Join-Path $env:TEMP "log.log"
        Write-Error "Log file not found, create new $File"
        $script:Log = $File
    }
    else {
        $File = $script:Log
    }
    Add-Content $File $content -ErrorAction Stop
}

function Set-Logger {
    <#
    .SYNOPSIS
    Sets default log file and stores in a script accessible variable $script:Log
    Log File name "packageExecution_$date.log"

    .PARAMETER Path
    Path to the log file

    .EXAMPLE
    Set-Logger
    Create a logger in
    #>

    Param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    # Create central log file with given date

    $date = Get-Date -UFormat "%Y-%m-%d %H-%M-%S"

    $commandPath = Get-Item $PSCommandPath
    $scriptName = "{0}_{1}" -f $commandPath.Directory.Name, $commandPath.Basename
    $scriptName = $scriptName -replace "-", ""

    Set-Variable logFile -Scope Script
    $script:logFile = "packageExecution_" + $scriptName + "_" + $date + ".log"

    if ((Test-Path $path ) -eq $false) {
        $null = New-Item -Path $path -type directory
    }

    $script:Log = Join-Path $path $logfile

    Add-Content $script:Log "Date`t`t`tCategory`t`tDetails"
}
#endregion


## MAIN
Set-Logger "C:\WindowsAzure\Logs\Plugins\PackageExecutionLogs\FSLogix" # inside "packageExecution_$scriptName_$date.log"

LogInfo("######################")
LogInfo("## Package: FSLogix ##")
LogInfo("######################")

LogInfo("#############")
LogInfo("# Load Data #")

$PsParam = Get-ChildItem -path "_deploy" -Filter $ConfigurationFileName -Recurse | Sort-Object -Property FullName
$ConfigurationFilePath = $PsParam.FullName

$ConfigurationJson = Get-Content -Path $ConfigurationFilePath -Raw -ErrorAction 'Stop'

try { $FSLogixConfig = $ConfigurationJson | ConvertFrom-Json -ErrorAction 'Stop' }
catch {
    Write-Error "Configuration JSON content could not be converted to a PowerShell object" -ErrorAction 'Stop'
}

foreach ($config in $FSLogixConfig.fslogix) {

    if ($config.installFSLogix) {

        LogInfo("###################")
        LogInfo("# Install FSLogix #")
        
        if ($PSCmdlet.ShouldProcess("FSLogix", "Install")) {
            & "$PSScriptRoot\Install-FSLogix.ps1"
            LogInfo("FSLogix installed")
        }
    }

    if ($config.configureFSLogix) {

        LogInfo("#####################")
        LogInfo("# Configure FSLogix #")
        
        foreach ($regSetting in $config.FSLogixRegistrySettings) {
            LogInfo ($regSetting.keyPath)
            foreach ($key in $regSetting.keyValues) {
                LogInfo($key.Name)
                LogInfo($key.Type)
                LogInfo($key.Value)
            }
        }
		
        foreach ($groupSetting in $config.FSLogixLocalGroupsSettings) {
            LogInfo ($groupSetting.localGroupName)
            foreach ($member in $groupSetting.members) {
                LogInfo($member)
            }
        }

        $($config.FSLogixRegistrySettings).GetType() | Format-Table
        Write-Verbose "Before function count: $($testArr.Count)"

        if ($PSCmdlet.ShouldProcess("FSLogix", "Set")) {
            & "$PSScriptRoot\Set-FSLogix.ps1" $config.FSLogixRegistrySettings $config.FSLogixLocalGroupsSettings
            LogInfo("FSLogix configured")
        }
    }

    if ($config.configureNTFSPermissions) {

        LogInfo("################################################")
        LogInfo("# Set NTFS permission on the share for FSLogix #")
        
        foreach ($NTFSSetting in $config.NTFSSettings) {
            LogInfo($NTFSSetting.filesharename)
            LogInfo($NTFSSetting.filesharestorageaccountname)
            LogInfo($NTFSSetting.domain)
            LogInfo($NTFSSetting.targetgroup)
            LogInfo($NTFSSetting.driveLetter)
        }
        
        LogInfo("Adding key to NTFS config")
        foreach ($setting in $config.NTFSSettings) {

            $key = ($Dynparameters.FSLogixKeys | Where-Object { $_.'StAName' -eq $setting.filesharestorageaccountname }).stakey
            $fileShareStorageAccountKey = convertto-securestring -string $key -asplaintext -force
                
            $setting | Add-Member -NotePropertyName 'fileShareStorageAccountKey' -NotePropertyValue $fileShareStorageAccountKey -force
            
        }
            
        if ($pscmdlet.shouldprocess("NTFS permissions on the share", "Set")) {
            & "$psscriptroot\set-ntfspermissions.ps1" $config.NTFSSettings
            LogInfo("permissions set")
        }
		
    }
}