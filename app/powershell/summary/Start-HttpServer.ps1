#Requires -Version 5.1

<#
.SYNOPSIS
    启动本地静态文件 HTTP 服务器，为 summary-viewer 提供 JSON 和静态资源访问。
#>

param(
    [Parameter(Mandatory = $true)]
    [int]$Port,

    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"

# 确保 System.Web 程序集已加载，用于 URL 解码
Add-Type -AssemblyName System.Web

# MIME 类型映射
$mimeMap = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.md'   = 'text/markdown; charset=utf-8'
    '.txt'  = 'text/plain; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
}

function Get-MimeType {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    if ($mimeMap.ContainsKey($ext)) {
        return $mimeMap[$ext]
    }
    return 'application/octet-stream'
}

$Root = Resolve-Path $Root | Select-Object -ExpandProperty Path
$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

# 向标准输出写入一行，便于 AHK 判断启动成功
Write-Host "HTTP server started at $prefix"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $localPath = [System.Web.HttpUtility]::UrlDecode($request.Url.LocalPath)
        # 去掉前导斜杠
        $relativePath = $localPath.TrimStart('/').Replace('/', '\')
        $fullPath = Join-Path $Root $relativePath

        try {
            if (Test-Path $fullPath -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($fullPath)
                $response.ContentType = Get-MimeType -Path $fullPath
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $response.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("Not Found: $localPath")
                $response.ContentLength64 = $msg.Length
                $response.OutputStream.Write($msg, 0, $msg.Length)
            }
        } catch {
            $response.StatusCode = 500
            $msg = [System.Text.Encoding]::UTF8.GetBytes("Internal Server Error: $_")
            $response.ContentLength64 = $msg.Length
            $response.OutputStream.Write($msg, 0, $msg.Length)
        } finally {
            $response.OutputStream.Close()
        }
    }
} finally {
    $listener.Stop()
}
