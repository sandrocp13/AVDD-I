[CmdletBinding(SupportsShouldProcess = $true)]
param (

    [Parameter(Mandatory = $false)]
    [Hashtable] $DynParameters,
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigurationFileName = "azfiles.parameters.json"
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
Set-Logger "C:\WindowsAzure\Logs\Plugins\PackageExecutionLogs\AzFiles" # inside "packageExecution_$scriptName_$date.log"

LogInfo("######################")
LogInfo("## Package: AzFiles ##")
LogInfo("######################")

LogInfo("#####################")
LogInfo("# Set Prerequisites #")

LogInfo("# Load parameters #")
LogInfo("# --------------- #")
# Convert azfile.parameters.json file
$PsParam = Get-ChildItem -path $PSScriptroot -Filter $ConfigurationFileName -Recurse | Sort-Object -Property FullName
$ConfigurationFilePath = $PsParam.FullName
$ConfigurationJson = Get-Content -Path $ConfigurationFilePath -Raw -ErrorAction 'Stop'
$ConfigurationJsonSanitized = $ConfigurationJson -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'
try { 
    $Config = $ConfigurationJsonSanitized | ConvertFrom-Json -ErrorAction 'Stop' 
}
catch {
    Write-Error "Configuration JSON content could not be converted to a PowerShell object" -ErrorAction 'Stop'
}
LogInfo("Parameters loaded from $($ConfigurationFilePath)")

LogInfo("# Set parameters #")
LogInfo("# -------------- #")
$Username = $Config.azfiles.StorageJoinUser
$KeyVaultName = $Config.azfiles.KeyVaultName

$NTLMDomain = (Get-WmiObject Win32_ComputerSystem).Domain
$NTLMUser = $Username.split("@")[0]
$NTLMStorageJoinUser = $NTLMDomain + "\" + $NTLMUser
LogInfo("Parameters set")

LogInfo("# Adding hybrid admin to local user admin group #")
LogInfo("# --------------------------------------------- #")
try {
    net localgroup Administrators $NTLMUser /add
    Start-Sleep -Seconds 15
} catch {
}
LogInfo("Prerequisites set")

LogInfo("###############")
LogInfo("# Get PSTools #")
        
if ($PSCmdlet.ShouldProcess("PSTools", "Get")) {
    & "$PSScriptRoot\Get-PSTools.ps1"
    LogInfo("PSTools expanded")
}

LogInfo("#########################")
LogInfo("# Install AzFilesHybrid #")
        
if ($PSCmdlet.ShouldProcess("AzFilesHybrid", "Install")) {
    & "$PSScriptRoot\Get-AzFilesHybrid.ps1"
    LogInfo("AzFilesHybrid installed")
}

LogInfo("#####################################################")
LogInfo("# Enable identity authentication on storage account #")

Set-Location $PSScriptRoot

LogInfo("# Get credentials from KeyVault #")
LogInfo("# ----------------------------- #")
# Retrieve hybrid admin user credentials from key vault
$Response = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -Method GET -Headers @{Metadata = "true" }
$KeyVaultToken = $Response.access_token
$KVSecretUri = 'https://' + $KeyVaultName + '.vault.azure.net/secrets/' + $NTLMUser + '-Password?api-version=2016-10-01'
$secret = Invoke-RestMethod -Uri $KVSecretUri -Method GET -Headers @{Authorization = "Bearer $KeyVaultToken" }

LogInfo("# Invoke Storage Join on behalf of hybrid admin #")
LogInfo("# --------------------------------------------- #")
$scriptPath1 = $($PSScriptRoot + "\Enable-ADAuthentication.ps1")
LogInfo("Calling $($scriptPath1)")
$scriptBlock = { .\PSTools\psexec /accepteula -h -i -w $PSScriptRoot -u $NTLMStorageJoinUser -p $secret.value powershell.exe "$scriptPath1" }
Invoke-Command $scriptBlock -Verbose