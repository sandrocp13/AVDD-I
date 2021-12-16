<#      
    .DESCRIPTION
    Main script performing the Windows VM extension deployment. Executed steps:
    - find all ZIP files in the downloaded folder (including subfolder).
    - extract all ZIP files to _deploy folder by also creating the folder.
    - each ZIP is extracted to a subfolder _deploy\<XXX>-<ZIP file name without extension> where XXX is a number starting at 000.
    - find all CSE_Run.ps1 files in _deploy subfolders.
    - execute all CSE_Run.ps1 scripts found in _deploy subfolders in the order of folder names and passing the DynParameters parameter from this script.

    .PARAMETER DynParameters
    Hashtable parameter enabling to pass Key-Value parameter pairs. Example: @{"Environment"="Prod";"Debug"="True"}  
    
    .PARAMETER startIndex
    The index of the item to start with installing. Useful when running a restart in between the installation of multiple packages. 
    If you specified 4 packages in your list of customizations and have a restart prior to the last one, provide the 'startIndex' 4 when re-invoking the installer script.
    BEWARE: To keep the flexibility of re-using packages, the start index refers not to the folder number in the 'Uploads' folder, but to slot in the list of customization steps you specified.
#>

[CmdletBinding(DefaultParametersetName = 'None')]
param(
    [Hashtable] [Parameter(Mandatory = $false)]
    [hashtable] $DynParameters = @{},

    [Parameter(Mandatory = $false)]
    [string] $downloadsPath = "",

    [Parameter(Mandatory = $false)]
    [int] $startIndex = 1
)

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
    Set-Variable logFile -Scope Script
    $script:logFile = "packageExecution_InitializeHost_$date.log"

    if ((Test-Path $path ) -eq $false) {
        $null = New-Item -Path $path -type directory
    }

    $script:Log = Join-Path $path $logfile

    Add-Content $script:Log "Date`t`t`tCategory`t`tDetails"
}
#endregion

Set-Logger "C:\WindowsAzure\Logs\Plugins\PackageExecutionLogs" # inside "packageExecution_$date.log"
$ErrorActionPreference = 'Stop'
LogInfo "Current working dir: $((Get-Location).Path)"

LogInfo "Unpacking zip files"

$zipSeachInputObject = @{
    Filter  = "*.zip" 
    Recurse = $true
}
if (-not [String]::IsNullOrEmpty($downloadsPath)) {
    $zipSeachInputObject['Path'] = $downloadsPath
}
$zipPackages = Get-ChildItem @zipSeachInputObject | Sort-Object -Property 'BaseName' # Makes sure Zips are picked up in the order of their number
if ($zipPackages) {
    LogInfo "Found $($zipPackages.count) zip packages"
}
else {
    LogError "No zip files found in the directory"
}

$i = 1
foreach ($zip in $zipPackages) {
    $destinationPath = "_deploy\{0}-{1}" -f $i.ToString("000"), $zip.BaseName # Beware: Assigns new incremental number to folder
    if (-not (Test-Path $destinationPath)) {
        LogInfo "Unpacking $($zip.FullName)"
        Expand-Archive -Path $zip.FullName -DestinationPath $destinationPath
    }
    $i++
}
LogInfo "Unpacking completed - Searching for package_run.ps1 files. Picking up at index [$startIndex]"

$PsScriptsToRun = Get-ChildItem -path "_deploy" -Filter "package_run.ps1" -Recurse | Sort-Object -Property FullName | Where-Object { $_.Directory.Name.Split('-')[0] -ge $startIndex.ToString("000") }

if ($PsScriptsToRun) {
    LogInfo "Found $($PsScriptsToRun.count) scripts"
}
else {
    LogError "No scripts found in the directory"
}

foreach ($scr in $PsScriptsToRun) {
    LogInfo "Running $($scr.FullName)"
    & $scr.FullName -DynParameters $DynParameters
}
LogInfo "Execution completed"