#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true)]
param (

    [Parameter(Mandatory = $false)]
    [Hashtable] $DynParameters,
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigurationFileName = "azfiles.parameters.json"
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

LogInfo("Setting location: $($PSScriptroot)")
Set-Location $PSScriptroot
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser -Force

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
$SubscriptionId = $Config.azfiles.SubscriptionId
$ResourceGroupName = $Config.azfiles.StorageResourceGroupName
$StorageAccounts = $Config.azfiles.StorageAccounts
$domainAccountType = $Config.azfiles.DomainAccountType
$orgUnit = $Config.azfiles.OUName
$KeyVaultName = $Config.azfiles.KeyVaultName
$OverwriteExistingADObject = $Config.azfiles.OverwriteExistingADObject
$NTLMDomain = (Get-WmiObject Win32_ComputerSystem).Domain
$NTLMUser = $Username.split("@")[0]
LogInfo("Parameters set")

LogInfo("# Importing modules #")
LogInfo("# ----------------- #")
$securityProtocol = [Net.ServicePointManager]::SecurityProtocol
if (-not($securityProtocol -eq 'Tls12')) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    LogInfo("Tls12 enabled")
}
Else {
    LogInfo("Tls12 already enabled")
}
Install-PackageProvider -Name NuGet -Force -Scope AllUsers
LogInfo("NuGet installed")
Install-Module `
    -Name PowerShellGet `
    -Repository PSGallery `
    -Force `
    -ErrorAction Stop `
    -SkipPublisherCheck `
    -Scope AllUsers
LogInfo("PowerShellGet installed")
Install-Module -Name Az.Accounts -AllowClobber -Force -ErrorAction Stop -Scope AllUsers
Install-Module -Name Az.Storage -AllowClobber -Force -ErrorAction Stop -Scope AllUsers
Install-Module -Name Az.Resources -AllowClobber -Force -ErrorAction Stop -Scope AllUsers
Install-Module -Name Az.Network -AllowClobber -Force -ErrorAction Stop -Scope AllUsers
LogInfo("Az modules installed successfully")

LogInfo("# Copy AzFilesHybrid module to PS Path #")
LogInfo("# ------------------------------------ #")
if ($PSCmdlet.ShouldProcess("AzFilesHybrid module to PS Path", "Copy")) {
    try {
        Set-Location ".\AzFilesHybrid"
        $Location = (Get-Location).Path
        $ScriptBlock = { powershell.exe $($Location + "\CopyToPSPath.ps1") }
        Invoke-Command $ScriptBlock -Verbose
        LogInfo("AzFilesHybrid module copied successfully")
    }
    catch {
        LogError("Failed to copy the AzFilesHybrid module into the PS path")
    }
}
Import-Module -Name AzFilesHybrid -Force -Verbose

LogInfo("# Azure Login #")
LogInfo("# ----------- #")
# Retrieve hybrid admin user credentials from key vault
$Response = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -Method GET -Headers @{Metadata = "true" }
$KeyVaultToken = $Response.access_token
$KVSecretUri = 'https://' + $KeyVaultName + '.vault.azure.net/secrets/' + $NTLMUser + '-Password?api-version=2016-10-01'
$secret = Invoke-RestMethod -Uri $KVSecretUri -Method GET -Headers @{Authorization = "Bearer $KeyVaultToken" }
# Connect to Azure
$Credential = New-Object System.Management.Automation.PsCredential($Username, (ConvertTo-SecureString $secret.value -AsPlainText -Force))
Connect-AzAccount -Credential $Credential
Select-AzSubscription -SubscriptionId $SubscriptionId
LogInfo("Successful login")

LogInfo("# Join storage account to AD #")
LogInfo("# -------------------------- #")
foreach ($StorageAccountName in $StorageAccounts) {
    LogInfo("Joining storage account $($StorageAccountName)")
    $StorageJoinInputs = @{
        ResourceGroupName                   = $ResourceGroupName
        StorageAccountName                  = $StorageAccountName
        DomainAccountType                   = $domainAccountType
        OrganizationalUnitDistinguishedName = $orgUnit
    }
    if ($OverwriteExistingADObject) {
        $StorageJoinInputs += @{ 
            OverwriteExistingADObject = $true 
        }
    }
    Join-AzStorageAccountForAuth @StorageJoinInputs
    $SANBDomainName = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).AzureFilesIdentityBasedAuth.ActiveDirectoryProperties.NetBiosDomainName
    if ($SANBDomainName -eq $NTLMDomain) {
        LogInfo("   Storage account $($StorageAccountName) successfully joined to the $($NTLMDomain) domain")   
    }
    else {
        LogInfo("   Unable to join Storage account $($StorageAccountName) to the $($NTLMDomain) domain")
    }
}