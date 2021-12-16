[CmdletBinding(SupportsShouldProcess = $true)]
param (

    [Parameter(Mandatory = $false)]
    [Hashtable] $DynParameters,
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigurationFileName = "teams.parameters.json"
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
$logPath = "C:\WindowsAzure\Logs\Plugins\PackageExecutionLogs\Teams"
Set-Logger $logPath # inside "packageExecution_$scriptName_$date.log"

LogInfo("####################")
LogInfo("## Package: Teams ##")
LogInfo("####################")

LogInfo("#############")
LogInfo("# Load Data #")

$PsParam = Get-ChildItem -path "_deploy" -Filter $ConfigurationFileName -Recurse | Sort-Object -Property FullName
$ConfigurationFilePath = $PsParam.FullName

$ConfigurationJson = Get-Content -Path $ConfigurationFilePath -Raw -ErrorAction 'Stop'

try { $TeamsConfig = $ConfigurationJson | ConvertFrom-Json -ErrorAction 'Stop' }
catch {
    Write-Error "Configuration JSON content could not be converted to a PowerShell object" -ErrorAction 'Stop'
}

foreach ($config in $TeamsConfig.Teams) {

    if ($config.configureTeams) {
        LogInfo("#############################")
        LogInfo("# Enable media optimization #")
        
        foreach ($regSetting in $config.teamsRegistrySettings) {
            LogInfo ($regSetting.keyPath)
            foreach ($key in $regSetting.keyValues) {
                LogInfo($key.Name)
                LogInfo($key.Type)
                LogInfo($key.Value)
            }
        }

        $($config.teamsRegistrySettings).GetType() | Format-Table
        Write-Verbose "Before function count: $($testArr.Count)"

        if ($PSCmdlet.ShouldProcess("Teams", "Set")) {
            & "$PSScriptRoot\Set-Teams.ps1" $config.teamsRegistrySettings
            LogInfo("Teams configured")
        }
    }

    if ($config.installTeams) {
        LogInfo("######################")
        LogInfo("# Install Visual C++ #")

        if ($PSCmdlet.ShouldProcess("Visual C++", "Install")) {
            & "$PSScriptRoot\Install-VisualCPP.ps1"
            LogInfo("Visual C++ installed")
        }

        LogInfo("#############################")
        LogInfo("# Install WebSocket Service #")

        if ($PSCmdlet.ShouldProcess("WebSocket Service", "Install")) {
            & "$PSScriptRoot\Install-WebSocket.ps1"
            LogInfo("WebSocket Service installed")
        }

        LogInfo("#################")
        LogInfo("# Install Teams #")

        if ($PSCmdlet.ShouldProcess("Teams", "Install")) {
            & "$PSScriptRoot\Install-Teams.ps1"
            LogInfo("Teams installed")
        }
    }

    
}