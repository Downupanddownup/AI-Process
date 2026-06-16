<#
.SYNOPSIS
    Opens a Markdown file in IntelliJ IDEA.

.DESCRIPTION
    Reads the IDEA executable path from AIProcess settings.ini and uses it
    to open the specified Markdown file.

.PARAMETER FilePath
    Absolute path to the Markdown file to open.
#>
[CmdletBinding()]
param(
    [Parameter(
        Mandatory = $true,
        Position = 0,
        HelpMessage = "Absolute path to the Markdown file"
    )]
    [ValidateNotNullOrEmpty()]
    [string]$FilePath
)

$ErrorActionPreference = "Stop"

# Resolve the path to settings.ini relative to this script's location.
# This script is expected to reside in the AIProcess app directory,
# alongside the config folder.
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDirectory "config\settings.ini"

function Read-IniValue {
    <#
    .SYNOPSIS
        Reads a single value from an INI file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $currentSection = $null

    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        $trimmedLine = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or
            $trimmedLine.StartsWith(";")) {
            continue
        }

        if ($trimmedLine -match "^\[(.+)\]$") {
            $currentSection = $matches[1]
            continue
        }

        if ($currentSection -eq $Section -and
            $trimmedLine -match "^(.+?)\s*=\s*(.*)$") {
            $currentKey = $matches[1].Trim()
            if ($currentKey -eq $Key) {
                return $matches[2].Trim()
            }
        }
    }

    return $null
}

function Assert-PathExists {
    <#
    .SYNOPSIS
        Verifies that a file or directory exists, otherwise exits with an error.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Error "$Description not found: $Path"
        exit 1
    }
}

# Validate settings file exists.
Assert-PathExists -Path $settingsPath -Description "settings.ini"

# Read IDEA command from settings.
$ideaCommand = Read-IniValue -Path $settingsPath -Section "Editor" -Key "IdeaCommand"
if ([string]::IsNullOrWhiteSpace($ideaCommand)) {
    Write-Error "IdeaCommand is not configured in settings.ini [Editor] section."
    exit 1
}

# Validate IDEA executable and target Markdown file exist.
Assert-PathExists -Path $ideaCommand -Description "IDEA executable"
Assert-PathExists -Path $FilePath -Description "Markdown file"

# Open the Markdown file with IDEA.
Start-Process -FilePath $ideaCommand -ArgumentList "`"$FilePath`"" -NoNewWindow

Write-Host "Opened '$FilePath' in IDEA."
