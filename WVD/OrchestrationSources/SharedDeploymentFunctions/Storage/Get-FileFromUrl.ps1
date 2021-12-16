<#
.SYNOPSIS
Download a the content of the provided url to a file with the provided name.

.DESCRIPTION
Download a the content of the provided url to a file with the provided name.

.PARAMETER Url
Specifies the URI from which to download data.

.PARAMETER FileName
Specifies the name of the local file that is to receive the data.

.PARAMETER Confirm
Will promt user to confirm the action to create invasible commands

.PARAMETER WhatIf
Dry run of the script

.EXAMPLE
Get-FileFromUrl -Url "https://aka.ms/fslogix_download" -FileName "FSLogixApp.zip"

Downloads file from the specified Uri and save it to the specified filepath 
#>

function Get-FileFromUrl {

    [CmdletBinding(SupportsShouldProcess = $True)]
    param(
        [Parameter(
            Mandatory,
            HelpMessage = "Specifies the URI from which to download data."
        )]
        [string] $Url,

        [Parameter(
            Mandatory,
            HelpMessage = "Specifies the name of the local file that is to receive the data."
        )]
        [string] $FileName
    )

    Write-Verbose "Getting current time." -Verbose
    $start_time = Get-Date

    try { 
        Write-Verbose "Starting download...." -Verbose
        if ($PSCmdlet.ShouldProcess("Required executable files from $url to $filename", "Import")) {
            (New-Object System.Net.WebClient).DownloadFile($Url, $FileName)
        }
        Write-Verbose "Download completed." -Verbose
        Write-Verbose "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)" -Verbose
    }
    catch {
        Write-Error "Download FAILED: $_"
    }
}