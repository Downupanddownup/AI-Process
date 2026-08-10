<#
.SYNOPSIS
    WPF 屏幕中央提示通知。

.DESCRIPTION
    在屏幕中央偏上位置显示一个半透明提示卡片，用于替代右下角 balloon tip。
    支持 -WindowId 参数显示窗口编号，无参数时显示默认"已完成"文本。
    不抢焦点、不中断输入、无声音，3 秒后自动淡出消失。

    可靠性设计：
    - 启动清场：杀掉同脚本旧实例，保证单实例（停旧播新），顺带清理卡死僵尸。
    - 兜底超时：独立线程看门狗 10 秒强制结束进程，Dispatcher 卡死也能触发。
    - 错误处理：Stop 模式 + try/catch/finally，任何异常都保证进程退出并留日志。
    - 点击穿透：WS_EX_TRANSPARENT，极端情况下窗口卡住也不拦截鼠标。
    - 预编译缓存：C# 编译为 DLL 缓存复用，源码变更自动重编译，失败降级现场编译。

.PARAMETER WindowId
    窗口编号，1 或 2 或 3。可选。
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2", "3")]
    [string]$WindowId = ""
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$activityLogScript = Join-Path $scriptDirectory "..\activity\WriteActivityLog.ps1"

# 写操作日志（失败静默忽略，日志不能反过来影响通知）
function Write-NotificationLog {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $false)][string]$Detail = ""
    )
    try {
        if (-not (Test-Path $activityLogScript)) { return }
        if ([string]::IsNullOrWhiteSpace($Detail)) {
            & powershell -ExecutionPolicy Bypass -File "$activityLogScript" -WindowId $WindowId -Action $Action
        } else {
            $detailFile = Join-Path $env:TEMP ("aiprocess_notify_detail_" + [guid]::NewGuid().ToString("N") + ".txt")
            [System.IO.File]::WriteAllText($detailFile, $Detail, [System.Text.Encoding]::UTF8)
            & powershell -ExecutionPolicy Bypass -File "$activityLogScript" -WindowId $WindowId -Action $Action -ContentFile "$detailFile"
        }
    } catch {
        # 静默忽略
    }
}

# 启动清场：结束同脚本的旧实例（含卡死僵尸），保证单实例
function Clear-OldNotificationInstances {
    $killed = 0
    try {
        $oldProcesses = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.ProcessId -ne $PID -and
                           $_.CommandLine -and
                           $_.CommandLine.Contains('ShowCenterNotification.ps1') }
        foreach ($proc in $oldProcesses) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                $killed++
            } catch {
                # 单个进程结束失败不影响其他
            }
        }
    } catch {
        # 查询失败不阻塞本次通知
    }
    if ($killed -gt 0) {
        Write-NotificationLog -Action "通知清场" -Detail "结束旧实例 $killed 个"
    }
}

try {
    Clear-OldNotificationInstances
    Write-NotificationLog -Action "通知开始"

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

    $csharpCode = @"
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Animation;
using System.Windows.Interop;
using System.Runtime.InteropServices;
using System.Windows.Threading;

public class NotificationWindow : Window {
    [DllImport("user32.dll")]
    static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    const int GWL_EXSTYLE = -20;
    const int WS_EX_NOACTIVATE = 0x08000000;
    const int WS_EX_TRANSPARENT = 0x00000020;

    private string windowNumber;
    // 独立线程看门狗：Dispatcher 卡死时也能触发，强制结束进程
    private System.Threading.Timer watchdog;

    public NotificationWindow(string windowNumber) {
        this.windowNumber = windowNumber;

        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = 0;
        Top = 0;
        Width = SystemParameters.PrimaryScreenWidth;
        Height = SystemParameters.PrimaryScreenHeight;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        Opacity = 0;
        UseLayoutRounding = true;

        SourceInitialized += OnSourceInitialized;
        ContentRendered += (s, e) => StartAnimations();
        BuildUI();

        // 兜底超时 10 秒（正常生命周期约 3.8 秒），到时进程必死
        watchdog = new System.Threading.Timer(
            _ => Environment.Exit(0),
            null, 10000, System.Threading.Timeout.Infinite);
    }

    private void OnSourceInitialized(object sender, EventArgs e) {
        IntPtr hwnd = new WindowInteropHelper(this).Handle;
        // WS_EX_TRANSPARENT：点击穿透，窗口即使卡住也不拦截鼠标
        SetWindowLong(hwnd, GWL_EXSTYLE, GetWindowLong(hwnd, GWL_EXSTYLE) | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT);
    }

    private void BuildUI() {
        var rootGrid = new Grid();
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(16) });
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(16) });

        var edgeBrush = new SolidColorBrush(Color.FromArgb(255, 0, 200, 255));
        var glowEffect = new DropShadowEffect {
            Color = Colors.Cyan,
            BlurRadius = 25,
            ShadowDepth = 0,
            Opacity = 0.8
        };

        var topBar = CreateEdgeBar(edgeBrush, glowEffect);
        Grid.SetRow(topBar, 0);
        rootGrid.Children.Add(topBar);

        var bottomBar = CreateEdgeBar(edgeBrush, glowEffect);
        Grid.SetRow(bottomBar, 2);
        rootGrid.Children.Add(bottomBar);

        var centerGrid = new Grid();
        Grid.SetRow(centerGrid, 1);
        centerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
        centerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        centerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });

        var leftBar = CreateEdgeBar(edgeBrush, glowEffect);
        Grid.SetColumn(leftBar, 0);
        centerGrid.Children.Add(leftBar);

        var rightBar = CreateEdgeBar(edgeBrush, glowEffect);
        Grid.SetColumn(rightBar, 2);
        centerGrid.Children.Add(rightBar);

        var contentCanvas = new Canvas {
            VerticalAlignment = VerticalAlignment.Stretch,
            HorizontalAlignment = HorizontalAlignment.Stretch
        };
        Grid.SetColumn(contentCanvas, 1);

        var card = CreateCard();
        contentCanvas.Children.Add(card);

        contentCanvas.SizeChanged += (s, ev) => {
            double cw = contentCanvas.ActualWidth;
            double ch = contentCanvas.ActualHeight;
            double cardX = cw / 2 - card.Width / 2;
            double cardY = ch / 3 - card.Height / 2;
            Canvas.SetLeft(card, cardX);
            Canvas.SetTop(card, cardY);
        };

        centerGrid.Children.Add(contentCanvas);
        rootGrid.Children.Add(centerGrid);

        Content = rootGrid;

        StartBreathing(topBar);
        StartBreathing(bottomBar);
        StartBreathing(leftBar);
        StartBreathing(rightBar);
    }

    private Border CreateEdgeBar(Brush brush, Effect effect) {
        return new Border {
            Background = brush,
            Effect = effect
        };
    }

    private Border CreateCard() {
        bool hasNumber = !string.IsNullOrEmpty(windowNumber);

        var card = new Border {
            Width = hasNumber ? 460 : 320,
            Height = 150,
            CornerRadius = new CornerRadius(20),
            Background = new SolidColorBrush(Color.FromArgb(150, 30, 30, 30)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(100, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            Effect = new DropShadowEffect {
                Color = Colors.Black,
                BlurRadius = 25,
                ShadowDepth = 0,
                Opacity = 0.6
            }
        };

        if (hasNumber) {
            var innerGrid = new Grid();
            innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Auto) });
            innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var numberBlock = new TextBlock {
                Text = windowNumber,
                FontFamily = new FontFamily("Microsoft YaHei UI"),
                FontSize = 80,
                FontWeight = FontWeights.Bold,
                Foreground = Brushes.White,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                VerticalAlignment = System.Windows.VerticalAlignment.Center,
                Margin = new Thickness(20, 0, 15, 0),
                Effect = new DropShadowEffect {
                    Color = Colors.Cyan,
                    BlurRadius = 15,
                    ShadowDepth = 0,
                    Opacity = 0.6
                }
            };
            Grid.SetColumn(numberBlock, 0);
            innerGrid.Children.Add(numberBlock);

            var textPanel = new StackPanel {
                Orientation = Orientation.Vertical,
                VerticalAlignment = System.Windows.VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 25, 0)
            };

            textPanel.Children.Add(new TextBlock {
                Text = "号窗",
                FontFamily = new FontFamily("Microsoft YaHei UI"),
                FontSize = 28,
                Foreground = new SolidColorBrush(Color.FromArgb(200, 255, 255, 255)),
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left
            });
            textPanel.Children.Add(new TextBlock {
                Text = "已完成",
                FontFamily = new FontFamily("Microsoft YaHei UI"),
                FontSize = 28,
                Foreground = new SolidColorBrush(Color.FromArgb(200, 255, 255, 255)),
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left
            });
            Grid.SetColumn(textPanel, 1);
            innerGrid.Children.Add(textPanel);

            card.Child = innerGrid;
        } else {
            var tb = new TextBlock {
                Text = "已完成",
                FontFamily = new FontFamily("Microsoft YaHei UI"),
                FontSize = 56,
                FontWeight = FontWeights.Bold,
                Foreground = Brushes.White,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
                VerticalAlignment = System.Windows.VerticalAlignment.Center,
                Effect = new DropShadowEffect {
                    Color = Colors.Cyan,
                    BlurRadius = 15,
                    ShadowDepth = 0,
                    Opacity = 0.6
                }
            };
            card.Child = tb;
        }

        return card;
    }

    private void StartBreathing(UIElement element) {
        var animation = new DoubleAnimation {
            From = 0.5,
            To = 1.0,
            Duration = new Duration(TimeSpan.FromMilliseconds(800)),
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever
        };
        element.BeginAnimation(UIElement.OpacityProperty, animation);
    }

    private void StartAnimations() {
        var fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(300));
        BeginAnimation(UIElement.OpacityProperty, fadeIn);

        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        timer.Tick += (s, ev) => {
            timer.Stop();
            var fadeOut = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(500));
            fadeOut.Completed += (s2, ev2) => {
                Close();
                Dispatcher.CurrentDispatcher.BeginInvokeShutdown(DispatcherPriority.Background);
            };
            BeginAnimation(UIElement.OpacityProperty, fadeOut);
        };
        timer.Start();
    }
}
"@

    # 预编译缓存：按源码哈希缓存 DLL，命中则直接加载，失败降级现场编译
    $cacheDir = Join-Path $scriptDirectory ".cache"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($csharpCode))
    $hashPrefix = ([BitConverter]::ToString($hashBytes)).Replace("-", "").Substring(0, 8)
    $cachedDll = Join-Path $cacheDir "NotificationWindow_$hashPrefix.dll"

    $typeLoaded = $false
    if (Test-Path $cachedDll) {
        try {
            Add-Type -Path $cachedDll
            $typeLoaded = $true
        } catch {
            # 缓存加载失败，降级为重新编译
            $typeLoaded = $false
        }
    }
    if (-not $typeLoaded) {
        $compiledToCache = $false
        try {
            if (-not (Test-Path $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }
            # -OutputAssembly 只负责编译落盘，不加载进会话，需再加载一次
            Add-Type -TypeDefinition $csharpCode -OutputAssembly $cachedDll `
                -ReferencedAssemblies PresentationFramework, PresentationCore, WindowsBase, System.Xaml
            Add-Type -Path $cachedDll
            $compiledToCache = $true
        } catch {
            # 写缓存失败，降级为纯内存现场编译
            $compiledToCache = $false
        }
        if (-not $compiledToCache) {
            Add-Type -TypeDefinition $csharpCode `
                -ReferencedAssemblies PresentationFramework, PresentationCore, WindowsBase, System.Xaml
        }
    }

    $window = New-Object NotificationWindow $WindowId
    $window.Show()
    [System.Windows.Threading.Dispatcher]::Run()

    # 通知显示完成后，写入操作日志
    Write-NotificationLog -Action "完成通知"
} catch {
    Write-NotificationLog -Action "通知异常" -Detail $_.Exception.Message
    exit 1
}
