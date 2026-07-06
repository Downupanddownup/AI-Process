#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [int]$Port,

    [string]$Root = "",

    [string]$LogFile = ""
)

function Write-Log($msg) {
    if ($LogFile) {
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [STOP] $msg"
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    }
}

try {
    Write-Log "Start. Port=$Port, Root=$Root"

    # 优先方法：读取 PID 文件并终止对应进程
    $pidFile = $null
    if ($Root -and (Test-Path $Root)) {
        $pidFile = Join-Path $Root 'app\logs\SummaryHttpServer.pid'
    } else {
        # 尝试从当前脚本位置推断 Root（app\powershell\summary\Stop-HttpServer.ps1）
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $pidFile = Join-Path $scriptDir '..\..\logs\SummaryHttpServer.pid'
        $pidFile = Resolve-Path $pidFile -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
    }

    Write-Log "pidFile=$pidFile"

    if ($pidFile -and (Test-Path $pidFile)) {
        $pidValue = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
        $pidValue = $pidValue.Trim()
        Write-Log "Read PID from file: $pidValue"
        if ($pidValue -match '^\d+$') {
            $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
            if ($proc) {
                Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
                Write-Log "Stopped process PID=$pidValue"
            } else {
                Write-Log "Process PID=$pidValue not found"
            }
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        Write-Log "Removed pidFile"
        exit 0
    }

    # 兜底方法1：按端口查找监听进程（HttpListener 可能显示为 System PID 4，不可靠）
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -eq '127.0.0.1' -or $_.LocalAddress -eq '0.0.0.0' } |
        Select-Object -First 1

    if ($conn) {
        Write-Log "Found connection: LocalAddress=$($conn.LocalAddress), LocalPort=$($conn.LocalPort), OwningProcess=$($conn.OwningProcess)"
        if ($conn.OwningProcess -gt 4) {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
            Write-Log "Stop-Process executed."
            exit 0
        } else {
            Write-Log "OwningProcess is System or idle, will try fallback by command line."
        }
    } else {
        Write-Log "No listening connection found on port $Port."
    }

    # 兜底方法2：查找执行 Start-HttpServer.ps1 的 powershell 进程
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Start-HttpServer.ps1*' }

    if ($procs) {
        Write-Log "Found $($procs.Count) powershell process(es) running Start-HttpServer.ps1"
        foreach ($proc in $procs) {
            Write-Log "Stopping process PID=$($proc.ProcessId)"
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Log "No powershell process found running Start-HttpServer.ps1"
    }

    exit 0
} catch {
    Write-Log "ERROR: $_"
    exit 1
}
