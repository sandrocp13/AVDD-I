[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [Hashtable] $DynParameters,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigurationFileName = "localization.config.json"
)

##########################################
# Has to run once for each user on logon #
##########################################

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
    $script:logFile = "script_" + $scriptName + "_" + $date + ".log"

    if ((Test-Path $path ) -eq $false) {
        $null = New-Item -Path $path -type directory
    }

    $script:Log = Join-Path $path $logfile

    Add-Content $script:Log "Date`t`t`tCategory`t`tDetails"
}
#endregion

Set-Logger "C:\WindowsAzure\Logs\Plugins\PackageExecutionLogs\OsLanguage" # inside "packageExecution_$scriptName_$date.log"

LogInfo("############################")
LogInfo("# Package: LanguageInstall #")
LogInfo("############################")

$PsParam = Get-ChildItem -path "_deploy" -Filter $ConfigurationFileName -Recurse | Sort-Object -Property FullName
$ConfigurationJson = Get-Content -Path $PsParam.FullName -Raw -ErrorAction 'Stop'

try { 
    $languageConfig = $ConfigurationJson | ConvertFrom-Json -ErrorAction 'Stop' 
}
catch {
    throw ("Configuration JSON content could not be converted to a PowerShell object: {0}" -f ($_ | Out-String ))
}
LogInfo("Parsed language configuration")

LogInfo("###########################")
LogInfo("# Install Languages on OS #")
$installInputObject = @{
    languagesToInstall = $languageConfig.languagesToInstall 
    osversion          = $languageConfig.osversion 
}
& "$PSScriptRoot\Install-OsLanguage.ps1" @installInputObject