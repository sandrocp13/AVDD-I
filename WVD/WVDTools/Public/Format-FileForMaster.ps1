<#
.SYNOPSIS
Format the parameter/variable file in the given path and replace its variables with '<ReplaceWith-XZY>' counterparts

.DESCRIPTION
Format the parameter/variable file in the given path and replace its variables with '<ReplaceWith-XZY>' counterparts
Excludes certain values like relative paths as they would not need to be changed by the user
You can leverage a 'WhatIf' switch to just print the result to the console.

.PARAMETER path
Mandatory. The variable/parameter file path to update

.PARAMETER exceptions
Optional. The variables/parameters to ignore. Already comes with a list.

.EXAMPLE
$filesIO = @{
    Path    = 'C:\dev\ip\IaCS\Solutions\Workloads\WVD\Environments'
    Exclude = @(
        'deploy.json',
        'rsv.backupmap.json',
        'pipeline.yml',
        'pipeline.steps.artifact.yml',
        'template.dpl.yml',
        'template.env.yml',
        'assets.config.json',
        'fslogix.parameters.json',
        'fslogix.MultistorageExample.parameters.json',
        'teams.parameters.json',
        'startOnConnectRoleAssignment.parameters.json',
        'startOnConnectRoleDefinition.parameters.json'
    )
    Include = @(
        '*.json',
        '*.yaml',
        '*.yml'
    )
    Recurse = $true
}
$filePaths = (Get-Childitem @filesIO).FullName
foreach($filePath in $filePaths) {
    Format-FileForMaster -path $filePath -Verbose
}

Overwrite all desired variable/parameter files in path 'C:\dev\ip\IaCS\Solutions\Workloads\WVD\Environments'
#>
function Format-FileForMaster {

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [string] $path,

        [Parameter(Mandatory = $false)]
        [string[]] $exceptions = @(
            'orchestrationPath',
            'orchestrationFunctionsPath',
            'wvdUploadsPath',
            'packagePath',
            'artifactFeedPath',
            '$schema',
            'contentVersion',
            'rgFolderPath',
            'pipelineName',
            'storageContainerMapPath',
            'anfModuleName',
            'resourceGroupModuleName',
            'storageAccountModuleName',
            'wvdHostPoolsModuleName',
            'wvdApplicationGroupsModuleName',
            'virtualMachinesModuleName',
            'wvdApplicationsModuleName',
            'wvdWorkspacesModuleName',
            'wvdScalingSchedulerModuleName',
            'msiModuleName',
            'rbacModuleName',
            'sharedImageGalleryModuleName',
            'sharedImageDefinitionModuleName',
            'imageTemplateModuleName',
            'roleDefinitionModuleName',
            'automationAccountModuleName',
            'rsvModuleName',
            'enabled',
            'moduleName',
            'enableWvdResources',
            'enableVmResources',
            'enableVmExtensions',
            'enablePostVmResources',
            'roleDefinitionIdOrName',
            'customRdpProperty',
            'AutopopulatedReadAndStartVMsRoleId',
            'createOption',
            'managedServiceIdentity',
            'synchronouslyWaitForImageBuild',
            'roleAssignments',
            'principalIds',
            'publicAccess',
            'roleDefinitionIdOrName'
        ),

        [Parameter(Mandatory = $false)]
        [switch] $overwrite
    )

    $content = Get-Content -Path $path
    $fileType = Split-Path $path -Extension

    if ($fileType -eq 'yaml') {
        $fileType = 'yml'
    }

    switch ($fileType) {
        '.json' {
            Write-Verbose 'Processing JSON'
            for ($rowIndex = 0; $rowIndex -lt $content.Count; $rowIndex++) {
                $varName = ''
                $suffix = ''
                $isString = $false



                # Pre-Processing
                # --------------
                if ($content[$rowIndex] -match '"([a-zA-Z]+)": ("[^"]+"|[^\,]+)(.*)') {
                    $suffix = $Matches[3]

                    $rowParts = $content[$rowIndex].Split(':')

                    $originalName = $rowParts[0] # needed to build the final string
                    $varName = $rowParts[0].Trim().Replace('"', '')
                }
                else {
                    # No variable row (e.g. comment)
                    continue
                }


                # Evaluate key
                if ($varName -in $exceptions) {
                    continue
                }

                if ($varName -eq 'value') {
                    $varName = $content[$rowIndex - 1].Split(':')[0].Trim().Replace('"', '')
                }

                # Evaluate value
                if ($rowParts.Count -gt 1) {
                    $value = $rowParts[1].TrimStart()

                    if ($value.StartsWith('"')) {
                        $isString = $true
                    }

                    if ($value -like "''*" -or $value -like "`"`"*" -or $value -match "{\s?$" -or $value -match "\[\s?$") {
                        # No value set in file
                        continue
                    }
                }

                # Processing
                # ----------
                if (-not [String]::IsNullOrEmpty($varName)) {
                    if ($varName.StartsWith('//')) {
                        # Special case -> row is well formatted, but a comment
                        $varName = $varName.Substring(2).TrimStart()
                    }
                    $capitalVar = $varName.substring(0, 1).toupper() + $varName.substring(1)
                    if ($isString) {
                        $newValue = "`"<ReplaceWith-$capitalVar>`"$suffix".Trim()
                    }
                    else {
                        $newValue = "<ReplaceWith-$capitalVar>$suffix".Trim()
                    }
                    $content[$rowIndex] = "{0}: {1}" -f $originalName, $newValue
                }
            }
        }
        '.yml' {
            Write-Verbose 'Processing YAML'

            if (($content | Where-Object { $_.Trim().StartsWith('- name:') } ).Count -gt 0 ) {
                Write-Verbose "Complex yaml"

                for ($rowIndex = 0; $rowIndex -lt $content.Count; $rowIndex++) {
                    $varName = ''
                    $comment = ''

                    if ($content[$rowIndex] -match "(\s*- group:)\s?'?`"?([^#\'\`"]+)'?`"?\s?(#.+)?") {
                        $originalIdentifier = $Matches[1]
                        $varName = $Matches[2]
                        if ($matches.Count -ge 3) {
                            $comment = $Matches[4]
                        }
                        $capitalVar = $varName.substring(0, 1).toupper() + $varName.substring(1)
                        $newValue = ("<ReplaceWith-{0}Group> $comment" -f $capitalVar).Trim()
                        $content[$rowIndex] = "$originalIdentifier $newValue"
                    }
                    elseif ($content[$rowIndex] -match '(\s*value:)') {

                        $originalIdentifier = $Matches[1]

                        # only proceed if previous row has 'name:' format
                        if(-not $content[$rowIndex -1].Trim().StartsWith('- name:')) {
                            continue
                        }

                        # extract name from previous row
                        $null = $content[$rowIndex - 1] -match "- name:\s?'?`"?([^#\'\`"]+)'?`"?\s?(#.+)?"

                        $varName = $Matches[1]

                        # Evaluate key
                        if ($varName -in $exceptions) {
                            continue
                        }

                        if ($matches.Count -ge 2) {
                            $comment = $Matches[2]
                        }

                        $capitalVar = $varName.substring(0, 1).toupper() + $varName.substring(1)
                        $newValue = ("<ReplaceWith-{0}> $comment" -f $capitalVar).Trim()
                        $content[$rowIndex] = "$originalIdentifier $newValue"
                    }
                }
            }
            else {
                Write-Verbose "Simple yaml"

                for ($rowIndex = 0; $rowIndex -lt $content.Count; $rowIndex++) {
                    $varName = ''
                    $comment = ''

                    # Pre-Processing
                    # --------------
                    if ($content[$rowIndex] -match '(.+):(.+)(#.*)') {
                        # With comment
                        $varName = $Matches[1].Trim()
                        $comment = $Matches[3]
                    }
                    elseif ($content[$rowIndex] -match '(.+):(.+)') {
                        # Without comment
                        $varName = $Matches[1].Trim()
                    }
                    else {
                        # No variable row (e.g. comment)
                        continue
                    }

                    $rowParts = $content[$rowIndex].Split(':')

                    # Evaluate key
                    if ($rowParts[0].Trim() -in $exceptions) {
                        continue
                    }

                    # Evaluate value
                    $value = $rowParts[1].TrimStart()
                    if ($value -like "''*" -or $value -like "`"`"*") {
                        # No value set in file
                        continue
                    }

                    # Processing
                    # ----------
                    if (-not [String]::IsNullOrEmpty($varName)) {
                        $capitalVar = $varName.substring(0, 1).toupper() + $varName.substring(1)
                        $newValue = "<ReplaceWith-$capitalVar> $comment".Trim()
                        $content[$rowIndex] = "{0}: {1}" -f $rowParts[0], $newValue
                    }
                }
            }
        }
        Default {
            throw "Unsupported file type [$fileType]"
        }
    }

    if ($PSCmdlet.ShouldProcess("File in path [$path]", "Overwrite")) {
        Set-Content -Path $path -Value $content -Force
    }
    else {
        return $content
    }
}
