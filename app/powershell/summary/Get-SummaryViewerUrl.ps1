#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$ThemePath,

    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [int]$Port,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile,

    [string]$LogFile = ""
)

function Write-Log($msg) {
    if ($LogFile) {
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [URL] $msg"
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    }
}

try {
    Write-Log "Start. ThemePath=$ThemePath, ProjectRoot=$ProjectRoot, Port=$Port, OutputFile=$OutputFile"

    $relativePath = $ThemePath -replace [regex]::Escape($ProjectRoot), ''
    Write-Log "RelativePath before replace: $relativePath"

    $jsonPath = ($relativePath -replace '\\', '/') + '/.aiprocess/Summary.json'
    Write-Log "JsonPath before leading slash check: $jsonPath"

    if ($jsonPath -notmatch '^/') {
        $jsonPath = '/' + $jsonPath
    }
    Write-Log "JsonPath after leading slash check: $jsonPath"

    $encodedPath = [System.Uri]::EscapeDataString($jsonPath)
    Write-Log "EncodedPath before %2F replace: $encodedPath"

    $encodedPath = $encodedPath -replace '%2F', '/'
    Write-Log "EncodedPath after %2F replace: $encodedPath"

    $url = "http://127.0.0.1:$Port/summary-viewer/index.html?json=$encodedPath"
    Write-Log "Output URL: $url"

    $url | Out-File -FilePath $OutputFile -Encoding utf8 -Force
    Write-Log "URL written to OutputFile"
    exit 0
} catch {
    Write-Log "ERROR: $_"
    exit 1
}
