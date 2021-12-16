
<#
.SYNOPSIS
Generates a region.xml (unattend.xml) file used to configure the language and region settings

.DESCRIPTION
Generates a region.xml (unattend.xml) file used to configure the language and region settings

.PARAMETER primaryOSLanguage
Primary location to use for e.g. region, user locale & system local

.PARAMETER fallbackOSUILanguage
Fallback UI language. By default en-US

.PARAMETER keyboardInputLanguages
The input languages (keyboard) languages to set. The first item in the list is set a the default.
Removes 'en-US' [0409:00000409] if not contained in the provided list.

.PARAMETER targetPath
Path to store the file in. Defaults to current directory

.EXAMPLE
New-RegionXml -primaryOSLanguage 'it-IT' -keyboardInputLanguages @('0410:00000410','0407:00000407')

Configure 'it-IT' as the primary locale as well as Italien & German as input languages
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true)]
    [string] $primaryOSLanguage,

    [Parameter(Mandatory = $false)]
    [string] $fallbackOSUILanguage = 'en-US',

    [Parameter(Mandatory = $true)]
    [string[]] $keyboardInputLanguages,

    [Parameter(Mandatory = $false)]
    [string] $targetPath = "$PSScriptRoot\region.xml"
)

$regionXml = New-Object 'System.Xml.XmlDocument'

$comment = @"

    Language configuration file to be applied post language package installation.
    Generated $(Get-Date)
    v1.0

"@

$regionXml.AppendChild($regionXml.CreateComment($comment)) | Out-Null

$root = $regionXml.CreateElement("gs", "GlobalizationServices", 'urn:longhornGlobalizationUnattend')

# USER LIST
# ---------
$root.AppendChild($regionXml.CreateComment('User List')) | Out-Null

$userList = $regionXml.CreateElement("gs", "UserList", 'urn:longhornGlobalizationUnattend')
$userListUser = $regionXml.CreateElement("gs", "User", 'urn:longhornGlobalizationUnattend')

$userAttrUserId = $regionXml.CreateAttribute("UserID", $null)
$userAttrUserId.Value = 'Current'
$userListUser.Attributes.SetNamedItem($userAttrUserId) | Out-Null

$userAttrCopySettUsAc = $regionXml.CreateAttribute("CopySettingsToDefaultUserAcct", $null)
$userAttrCopySettUsAc.Value = 'true'
$userListUser.Attributes.SetNamedItem($userAttrCopySettUsAc) | Out-Null

$userAttrCopySettSysAc = $regionXml.CreateAttribute("CopySettingsToSystemAcct", $null)
$userAttrCopySettSysAc.Value = 'true'
$userListUser.Attributes.SetNamedItem($userAttrCopySettSysAc) | Out-Null

$userList.AppendChild($userListUser) | Out-Null
$root.AppendChild($userList) | Out-Null

# LOCATION PREFERENCE
# -------------------
$root.AppendChild($regionXml.CreateComment('LocationPreferences')) | Out-Null
# Ref https://docs.microsoft.com/en-us/windows/win32/intl/table-of-geographical-locations

$locationPReferences = $regionXml.CreateElement("gs", "LocationPreferences", 'urn:longhornGlobalizationUnattend')
$geoId = $regionXml.CreateElement("gs", "GeoID", 'urn:longhornGlobalizationUnattend')

$geoAttrValue = $regionXml.CreateAttribute("Value", $null)
$geoAttrValue.Value = (New-Object -TypeName System.Globalization.RegionInfo($primaryOSLanguage)).GeoId
$geoId.Attributes.SetNamedItem($geoAttrValue) | Out-Null

$locationPReferences.AppendChild($geoId) | Out-Null
$root.AppendChild($locationPReferences) | Out-Null

# MUI LANGUAGE PREFERENCE
# -----------------------
$root.AppendChild($regionXml.CreateComment('MUILanguagePreferences')) | Out-Null

$MUILanguagePreferences = $regionXml.CreateElement("gs", "MUILanguagePreferences", 'urn:longhornGlobalizationUnattend')
$MUILanguage = $regionXml.CreateElement("gs", "MUILanguage", 'urn:longhornGlobalizationUnattend')

$muiAttrValue = $regionXml.CreateAttribute("Value", $null)
$muiAttrValue.Value = $fallbackOSUILanguage
$MUILanguage.Attributes.SetNamedItem($muiAttrValue) | Out-Null

$MUILanguagePreferences.AppendChild($MUILanguage) | Out-Null

# Fallback
$MUIFallback = $regionXml.CreateElement("gs", "MUIFallback", 'urn:longhornGlobalizationUnattend')

$muiAttrValue = $regionXml.CreateAttribute("Value", $null)
$muiAttrValue.Value = $primaryOSLanguage
$MUIFallback.Attributes.SetNamedItem($muiAttrValue) | Out-Null

$MUILanguagePreferences.AppendChild($MUIFallback) | Out-Null

$root.AppendChild($MUILanguagePreferences) | Out-Null

# SYSTEM LOCALE
# -------------
$root.AppendChild($regionXml.CreateComment('System Locale')) | Out-Null

$systemLocale = $regionXml.CreateElement("gs", "SystemLocale", 'urn:longhornGlobalizationUnattend')

$systemLocaleAttrName = $regionXml.CreateAttribute("Name", $null)
$systemLocaleAttrName.Value = $primaryOSLanguage
$systemLocale.Attributes.SetNamedItem($systemLocaleAttrName) | Out-Null

$root.AppendChild($systemLocale) | Out-Null

# USER LOCALE
# -----------
$root.AppendChild($regionXml.CreateComment('User Locale')) | Out-Null

$UserLocale = $regionXml.CreateElement("gs", "UserLocale", 'urn:longhornGlobalizationUnattend')
$Locale = $regionXml.CreateElement("gs", "Locale", 'urn:longhornGlobalizationUnattend')

$localAttrName = $regionXml.CreateAttribute("Name", $null)
$localAttrName.Value = $primaryOSLanguage
$Locale.Attributes.SetNamedItem($localAttrName) | Out-Null

$localAttrCurrent = $regionXml.CreateAttribute("SetAsCurrent", $null)
$localAttrCurrent.Value = 'true'
$Locale.Attributes.SetNamedItem($localAttrCurrent) | Out-Null

$localAttrReset = $regionXml.CreateAttribute("ResetAllSettings", $null)
$localAttrReset.Value = 'false'
$Locale.Attributes.SetNamedItem($localAttrReset) | Out-Null

$UserLocale.AppendChild($Locale) | Out-Null
$root.AppendChild($UserLocale) | Out-Null

# INPUT PREFERENCES
# -----------------
$root.AppendChild($regionXml.CreateComment('Input Preferences')) | Out-Null
# Ref https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-input-locales-for-windows-language-packs

$InputPreferences = $regionXml.CreateElement("gs", "InputPreferences", 'urn:longhornGlobalizationUnattend')
for ($count = 0; $count -lt $keyboardInputLanguages.Count; $count++) {
    $inputPreferenceId = $keyboardInputLanguages[$count]

    $InputLanguageIDAdd = $regionXml.CreateElement("gs", "InputLanguageID", 'urn:longhornGlobalizationUnattend')

    $inputAddAttAction = $regionXml.CreateAttribute("Action", $null)
    $inputAddAttAction.Value = 'add'
    $InputLanguageIDAdd.Attributes.SetNamedItem($inputAddAttAction) | Out-Null

    $inputAddAttId = $regionXml.CreateAttribute("ID", $null)
    $inputAddAttId.Value = $inputPreferenceId
    $InputLanguageIDAdd.Attributes.SetNamedItem($inputAddAttId) | Out-Null

    if ($count -eq 0) {
        # First element is treated as default
        $inputAddAttDefault = $regionXml.CreateAttribute("Default", $null)
        $inputAddAttDefault.Value = 'true'
        $InputLanguageIDAdd.Attributes.SetNamedItem($inputAddAttDefault) | Out-Null
    }

    $InputPreferences.AppendChild($InputLanguageIDAdd) | Out-Null
}

if ($keyboardInputLanguages -notcontains '0409:00000409') {
    # Remove en-US if not configured to remain
    $InputLanguageIDRem = $regionXml.CreateElement("gs", "InputLanguageID", 'urn:longhornGlobalizationUnattend')

    $inputRemAttAction = $regionXml.CreateAttribute("Action", $null)
    $inputRemAttAction.Value = 'remove'
    $InputLanguageIDRem.Attributes.SetNamedItem($inputRemAttAction) | Out-Null

    $inputRemAttId = $regionXml.CreateAttribute("ID", $null)
    $inputRemAttId.Value = '0409:00000409'
    $InputLanguageIDRem.Attributes.SetNamedItem($inputRemAttId) | Out-Null

    $InputPreferences.AppendChild($InputLanguageIDRem) | Out-Null
}
$root.AppendChild($InputPreferences) | Out-Null

#add root to the document
$regionXml.AppendChild($root) | Out-Null

if ($PSCmdlet.ShouldProcess("XML file", "Create")) {
    $regionXml.Save($targetPath) | Out-Null
}

# Slightly formatted output
return ($regionXml.InnerXml.Split('<') -join "`n<")