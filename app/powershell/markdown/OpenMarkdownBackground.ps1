<#
.SYNOPSIS
    MD 后台模式：以非激活方式用 IDEA 打开 Markdown 文件，并显示中央提示。

.DESCRIPTION
    读取 settings.ini 中的 IdeaCommand，使用 Win32 CreateProcess + SW_SHOWNOACTIVATE
    启动 IDEA 打开 Markdown 文件，不激活 IDEA 窗口。随后调用 ShowCenterNotification.ps1
    显示中央提示。

.PARAMETER FilePath
    要打开的 Markdown 文件绝对路径。

.PARAMETER WindowId
    窗口编号，1 或 2。可选。
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2")]
    [string]$WindowId = ""
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDirectory "..\..\config\settings.ini"
$notificationScript = Join-Path $scriptDirectory "..\..\powershell\notification\ShowCenterNotification.ps1"

function Read-IniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $currentSection = $null
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith(";")) {
            continue
        }
        if ($trimmedLine -match "^\[(.+)\]$") {
            $currentSection = $matches[1]
            continue
        }
        if ($currentSection -eq $Section -and $trimmedLine -match "^(.+?)\s*=\s*(.*)$") {
            $currentKey = $matches[1].Trim()
            if ($currentKey -eq $Key) {
                return $matches[2].Trim()
            }
        }
    }
    return $null
}

function Assert-PathExists {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path -Path $Path)) {
        Write-Error "$Description not found: $Path"
        exit 1
    }
}

Assert-PathExists -Path $settingsPath -Description "settings.ini"
Assert-PathExists -Path $notificationScript -Description "Notification script"

$ideaCommand = Read-IniValue -Path $settingsPath -Section "Editor" -Key "IdeaCommand"
if ([string]::IsNullOrWhiteSpace($ideaCommand)) {
    Write-Error "IdeaCommand is not configured in settings.ini [Editor] section."
    exit 1
}

Assert-PathExists -Path $ideaCommand -Description "IDEA executable"
Assert-PathExists -Path $FilePath -Description "Markdown file"

# 使用 Win32 CreateProcess + SW_SHOWNOACTIVATE 启动 IDEA，避免激活窗口
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

public class NoActivateLauncher {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcess(
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    const int STARTF_USESHOWWINDOW = 0x0001;
    const int SW_SHOWNOACTIVATE = 4;

    public static void Launch(string exe, string args) {
        var si = new STARTUPINFO();
        si.cb = System.Runtime.InteropServices.Marshal.SizeOf(si);
        si.dwFlags = STARTF_USESHOWWINDOW;
        si.wShowWindow = SW_SHOWNOACTIVATE;

        PROCESS_INFORMATION pi;
        bool success = CreateProcess(exe, args, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, null, ref si, out pi);
        if (!success) {
            throw new Win32Exception(System.Runtime.InteropServices.Marshal.GetLastWin32Error());
        }
    }
}
"@ -ReferencedAssemblies System.Runtime.InteropServices

try {
    [NoActivateLauncher]::Launch($ideaCommand, "`"$FilePath`"")
    Write-Host "Opened '$FilePath' in IDEA without activating window."
} catch {
    Write-Error "Failed to launch IDEA without activation: $_"
    exit 1
}

# 调用中央提示
$notifyArgs = @("-ExecutionPolicy", "Bypass", "-File", "`"$notificationScript`"")
if ($WindowId -ne "") {
    $notifyArgs += @("-WindowId", "`"$WindowId`"")
}

Start-Process -FilePath "powershell" -ArgumentList $notifyArgs -NoNewWindow
