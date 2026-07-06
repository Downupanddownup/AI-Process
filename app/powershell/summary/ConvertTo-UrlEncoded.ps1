#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$Text
)

[System.Uri]::EscapeDataString($Text)
