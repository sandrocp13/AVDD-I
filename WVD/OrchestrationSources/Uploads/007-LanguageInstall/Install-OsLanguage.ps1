# Source : https://docs.microsoft.com/en-us/azure/virtual-desktop/language-packs
# GeoLocation: https://docs.microsoft.com/en-gb/windows/win32/intl/table-of-geographical-locations?redirectedfrom=MSDN

<#
Available parameters:
- languagesToInstall: e.g. de-de
- version: e.g. 2004. only needed if multiple versions are specified in 'downloads'
- downloads: The download urls of the LanguagePack & FOD ISOs
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $configurationPath = "$PSScriptRoot\language.iso.sources.json",

    [Parameter(Mandatory = $true)]
    [string[]] $languagesToInstall,
    
    [Parameter(Mandatory = $false)]
    [string] $osversion
)

$env:scriptExecutionData = Get-Date -UFormat "%Y-%m-%d %H-%M-%S"

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

function Get-RemoteFiles {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable[]] $downloads
    )
    
    $downloadJobs = @()
    foreach ($download in $downloads) {
        $downloadJobs += Start-Job -Arg $download -ScriptBlock { 

            param(
                [Parameter(Mandatory)]
                [Hashtable] $download
            )

            Write-Output ("Checking file [{0}]" -f $download.targetPath)
            if (-not (Test-Path $download.targetPath)) {
                if (-not (Test-Path (Split-Path $download.targetPath -Parent))) {
                    Write-Output ("Download path [{0}] not existing. Creating." -f (Split-Path $download.targetPath -Parent))
                    New-Item -ItemType 'Directory' -Path (Split-Path $download.targetPath -Parent) -Force
                }

                Write-Output ("Downloading file [{0}] from url [{1}]" -f $download.remoteFileName, $download.sourceUrl)
                (New-Object System.Net.WebClient).DownloadFile($download.sourceUrl, $download.targetPath) # DownloadFileAsync
                Write-Output ("Download of file [{0}] complete" -f $download.targetPath)
            }
            else {
                Write-Output ('File [{0}] already exists' -f $download.targetPath)
            }
        }
    }
    return $downloadJobs
}
#endregion

#####################
## STANDALONE CODE ##
#####################
Set-Logger "C:\WindowsAzure\Logs\Plugins\PackageExecutionLogs\OsLanguage" # inside "packageExecution_$scriptName_$date.log"

$StartTime = Get-Date

LogInfo("# Prepare data #")
LogInfo("# ------------ #")

# Handle configuration file
LogInfo("Path to configuration file provided: [$configurationPath]")
$configurationFile = ConvertFrom-Json (Get-Content $configurationPath -Raw)

# Convert downloads to Hashtable
LogInfo("Formatting download [{0}] entries" -f $configurationFile.downloads.count)
$downloads = @()
foreach ($downloadObject in $configurationFile.downloads) {
    $downloadsEntry = @{}
    $downloadObject.psobject.properties | Foreach-Object { $downloadsEntry[$_.Name] = $_.Value }
    $downloads += $downloadsEntry
}

# Filter to required osversion
if (-not [String]::IsNullOrEmpty($osversion)) {
    LogInfo("Filtering [{0}] downloads for OS version [{1}]" -f $downloads.Count, $osversion)
    $downloads = $downloads | Where-Object { $_.osversion -eq $osversion }
    LogInfo("Filtered down to [{0}] elements" -f $downloads.Count)
}

## PRINTING THE CONFIGURATION
LogInfo("Used configuration")
LogInfo("==================")
LogInfo("Languages to install:           {0}" -f ($languagesToInstall -join ', '))
LogInfo("(optional) File version filter: $osversion")

foreach ($download in $downloads) {
    $fileName = Split-Path $download.sourceUrl -Leaf
    if ([String]::IsNullOrEmpty($download.targetFileName)) { $targetFileName = $fileName } 
    else { $targetFileName = $download.targetFileName }

    if ([String]::IsNullOrEmpty($download.targetBasePath)) { 
        $downloadBasePath = 'c:\temp'
        if (-not (Test-Path $downloadBasePath)) {
            New-Item -Path $downloadBasePath -ItemType 'Directory' | Out-Null
        }
        $targetBasePath = $downloadBasePath 
    }
    else { $targetBasePath = $download.targetBasePath }
    
    $download.remoteFileName = $fileName
    $download.targetFileName = $targetFileName
    $download.targetPath = Join-Path $targetBasePath $targetFileName
    LogInfo("Configure download of [{0}] to path [{1}]" -f $download.remoteFileName, $download.targetPath)
}

# Step 1: Download language & FOD iso
LogInfo("# Download language & FOD iso #")
LogInfo("# --------------------------- #")

LogInfo('Initiate download from [{0}] sources' -f $downloads.Count)
$downloadJobs = Get-RemoteFiles -downloads $downloads
LogInfo('Waiting for [{0}] downloads' -f $downloadJobs.length)
$StartTime = get-date
$output = $downloadJobs | Wait-Job | Receive-Job
$elapsedTime = (get-date) - $StartTime
$totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks) 
LogInfo("Download(s) complete. It took [{0}]. Output: `n{1}" -f $totalTime, ($output -join "`n"))

# Step 2: Mount ISOs
LogInfo("# Mount ISOs #")
LogInfo("# ---------- #")
foreach ($download in $downloads) {

    if (-not (Get-DiskImage $download.targetPath | Get-Volume)) {
        Mount-DiskImage -ImagePath $download.targetPath -ErrorAction 'SilentlyContinue' | Out-Null
    }
    switch ($download.scope) {
        'language' {
            $mountedLangPath = "{0}:" -f (Get-DiskImage $download.targetPath | Get-Volume).DriveLetter
            break
        }
        'fod' { 
            $mountedFodPath = "{0}:" -f (Get-DiskImage $download.targetPath | Get-Volume).DriveLetter
            break
        }
        'inboxapps' {
            $mountedInboxAppsPath = "{0}:" -f (Get-DiskImage $download.targetPath | Get-Volume).DriveLetter
            break
        }
        Default {
            throw ('Unknown scope {0}' -f $download.scope)
        }
    }
}

LogInfo "Disable App Cleanup"
Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "Pre-staged app cleanup" | Out-Null 

# Step 3: Set required regex paths to allow 'specialprofile' deployments
LogInfo("Set required regex paths to allow 'specialprofile' deployments")
$fsLogixRegPath = "HKLM:\Software\Policies\Microsoft\Windows"
$expectedReqKey = 'Appx'
$expectedfRegKeyPath = Join-Path $fsLogixRegPath $expectedReqKey
$expectedValues = @(
    @{
        Name  = 'AllowDeploymentInSpecialProfiles'
        Type  = 'DWORD'
        Value = '1'
    }
)
if (-not (Test-Path $expectedfRegKeyPath)) {
    LogInfo("RegexPath '$expectedfRegKeyPath' not existing. Creating")
    New-Item -Path $expectedfRegKeyPath -Force | Out-Null
}

LogInfo("Creating values")
$expectedValues | ForEach-Object {
    LogInfo('Creating entry "{0}" of type "{1}" with value "{2}" in path "{3}"' -f $_.Name, $_.Type, $_.Value, $expectedfRegKeyPath)
    $inputObject = @{
        Path         = $expectedfRegKeyPath
        Name         = $_.Name
        Value        = $_.Value
        PropertyType = $_.Type
    }
    New-ItemProperty @inputObject -Force | Out-Null
}

# Step 4: Apply language packs
LogInfo("# Apply language packs #")
LogInfo("# -------------------- #")

# Disable Language Pack Clenaup
# -----------------------------
Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "Pre-staged app cleanup" | Out-Null

# Prepare paths
$languageBasePath = Join-Path $mountedLangPath 'LocalExperiencePack'
$languagePackPath = Join-Path $mountedLangPath 'x64\langpacks' 
$fodPath = $mountedFodPath

foreach ($language in $languagesToInstall) {

    LogInfo("## Language [$language]")
    LogInfo("## ---------------")

    # Language packages
    # -----------------
    $packagePath = "$languageBasePath\$language\LanguageExperiencePack.$language.Neutral.appx"
    $licencePath = "$languageBasePath\$language\License.xml"

    LogInfo("Add <App Provisioned Package> [$packagePath] with lincence [$licencePath]")   
    if ($PSCmdlet.ShouldProcess("Provisioned package", "Add")) {
        try { Add-AppProvisionedPackage -Online -PackagePath $packagePath -LicensePath $licencePath | Out-Null }
        catch { LogError ("ERROR: {0}" -f $_.Exception.Message) }
    }

    # Windows packs
    # -------------
    $windowsPacks = [System.Collections.ArrayList]@()
    $windowsPacks += "$languagePackPath\Microsoft-Windows-Client-Language-Pack_x64_$language.cab"
    

    # Feature On Demand
    $fodElements = Get-Childitem -Path $fodPath -Filter "*$language*" 
    foreach ($fodElement in $fodElements) {
        $windowsPacks += $fodElement.FullName
    }

    $windowsPacks | ForEach-Object {    
        LogInfo("Adding <Windows Package> [$_]")
        if ($PSCmdlet.ShouldProcess("Windows Packge [$_]", "Add")) {
            try { 
                #    Add-WindowsPackage -Online -PackagePath $_ -NoRestart | Out-Null 
                & $env:SystemRoot\\System32\\Dism.exe /online /norestart /Add-Package /PackagePath:$_ | Out-Null
            } 
            catch { LogError ("ERROR: {0}" -f $_.Exception.Message) }
        }
    }
}

# Step 5: Refresh Inbox Apps
LogInfo("# Update Inbox Apps for Multi Language #")
LogInfo("# ------------------------------------ #")

$mountedInboxAppsPath = Join-Path $mountedInboxAppsPath 'amd64fre'
#$AllAppx = Get-Item "$mountedInboxAppsPath\*.appx" | Select-Object name
$AllAppxBundles = Get-Item "$mountedInboxAppsPath\*.appxbundle" | Select-Object name
$allAppxXML = Get-Item "$mountedInboxAppsPath\*.xml" | Select-Object name

# Some files are only for the parameter dependencyPackagePath?
# e.g. - H:\amd64fre\Microsoft.NET.Native.Framework.x64.1.7.appx
foreach ($Appx in $AllAppx) {
    $appname = $appx.name.substring(0, $Appx.name.length - 5)
    LogInfo("Handling App [$appname]")

    $appnamexml = $appname + ".xml"
    $pathappx = $mountedInboxAppsPath + "\" + $appx.Name
    $pathxml = $mountedInboxAppsPath + "\" + $appnamexml

    if ($allAppxXML.name -contains $appnamexml) {  
        if ($PSCmdlet.ShouldProcess("Appx provisioned package [$pathappx]", "Add")) {
            try { Add-AppxProvisionedPackage -Online -PackagePath $pathappx -LicensePath $pathxml | Out-Null }
            catch { LogError ("ERROR: {0}" -f $_.Exception.Message) }
        }
    }
    else {   
        if ($PSCmdlet.ShouldProcess("Appx provisioned package [$pathappx]", "Add")) {   
            try { Add-AppxProvisionedPackage -Online -PackagePath $pathappx -skiplicense | Out-Null }
            catch { LogError ("ERROR: {0}" -f $_.Exception.Message) }
        }
    }
}

foreach ($Appx in $AllAppxBundles) {
    $appname = $appx.name.substring(0, $Appx.name.length - 11)

    LogInfo("Handling AppBundle [$appname]")

    $appnamexml = $appname + ".xml"
    $pathappx = $mountedInboxAppsPath + "\" + $appx.Name
    $pathxml = $mountedInboxAppsPath + "\" + $appnamexml
    try {
        if ($allAppxXML.name -contains $appnamexml) {  
            if ($PSCmdlet.ShouldProcess("Appx provisioned package [$pathappx]", "Add")) {
                try { Add-AppxProvisionedPackage -Online -PackagePath $pathappx -LicensePath $pathxml | Out-Null }
                catch { LogError ("ERROR: {0}" -f $_.Exception.Message) }
            }
        }
        else {   
            if ($PSCmdlet.ShouldProcess("Appx provisioned package [$pathappx]", "Add")) {   
                try { Add-AppxProvisionedPackage -Online -PackagePath $pathappx -skiplicense | Out-Null }
                catch { LogError ("ERROR: {0}" -f $_.Exception.Message) }
            }
        }
    } 
    catch {
        LogError("Appx [{0}] installation failed: [{1}]" -f $pathappx, ($_ | Out-String))
    }
}

# Step 6: Remove ISO files & unmount drives
LogInfo("# Remove ISO files & unmount drives #")
LogInfo("# --------------------------------- #")
foreach ($download in $downloads) {
    $isoFileName = Split-Path $download.targetPath -Leaf
    LogInfo("Unmount ISO [$isoFileName]")
    Dismount-DiskImage $download.targetPath | Out-Null

    LogInfo("Remove ISO [$isoFileName]")
    Remove-Item -Path $download.targetPath -Force | Out-Null
}

$elapsedTime = (get-date) - $StartTime
$totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
LogInfo("Execution took [$totalTime]")
LogInfo("Exiting Install-OsLanguage.ps1")