#Requires -RunAsAdministrator

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

Set-Logger "C:\WindowsAzure\Logs\Plugins\PackageExecutionLogs\AzFiles" # inside "packageExecution_$scriptName_$date.log"

LogInfo("# Download PSTools #")
LogInfo("# ---------------- #")

$installBasePath = $PSScriptRoot
$PSToolsArchivePath = Join-Path $installBasePath "PSTools.zip"
If (-Not (Test-Path -Path $PSToolsArchivePath)) {

    # Store software in new location as required by AIB
    $installBasePath = 'C:/WindowsAzure/Software'
    If (-Not(Test-Path -Path $installBasePath)) {
        New-Item -Path $installBasePath -ItemType 'Directory' 
    }
    $PSToolsArchivePath = Join-Path $installBasePath "PSTools.zip"

    $StartTime = Get-Date
    $Url = "https://download.sysinternals.com/files/PSTools.zip"
    LogInfo("Starting download....")
    try { 
        if ($PSCmdlet.ShouldProcess("Required executable files from $url to $PSToolsArchivePath", "Import")) {
            (New-Object System.Net.WebClient).DownloadFile($Url, $PSToolsArchivePath)
        }
    }
    catch {
        LogError("Download FAILED: $_")
    }
    $elapsedTime = (get-date) - $StartTime
    $totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks) 
    LogInfo("Download(s) complete. It took [{0}]." -f $totalTime)
}


LogInfo("# Extract PSTools #")
LogInfo("# --------------- #")

$ExtractionTargetPath = "$installBasePath\PSTools"

LogInfo("Expanding Archive $PSToolsArchivePath into $ExtractionTargetPath")
if (-not (Test-Path $ExtractionTargetPath)) {
    Expand-Archive -Path $PSToolsArchivePath -DestinationPath $ExtractionTargetPath
    LogInfo("Archive expanded")
}
else {
    LogInfo("Files already exist path path [$ExtractionTargetPath]: {0}" -f (Get-ChildItem (Split-Path $ExtractionTargetPath -Parent) | Out-String))
}