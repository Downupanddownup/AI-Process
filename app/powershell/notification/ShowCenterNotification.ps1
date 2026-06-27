<#
.SYNOPSIS
    WPF 屏幕中央提示通知。

.DESCRIPTION
    在屏幕中央偏上位置显示一个半透明提示卡片，用于替代右下角 balloon tip。
    支持 -WindowId 参数显示窗口编号，无参数时显示默认"已完成"文本。
    不抢焦点、不中断输入、无声音，3 秒后自动淡出消失。

.PARAMETER WindowId
    窗口编号，1 或 2。可选。
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("1", "2", "3")]
    [string]$WindowId = ""
)

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

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

    private string windowNumber;

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
    }

    private void OnSourceInitialized(object sender, EventArgs e) {
        IntPtr hwnd = new WindowInteropHelper(this).Handle;
        SetWindowLong(hwnd, GWL_EXSTYLE, GetWindowLong(hwnd, GWL_EXSTYLE) | WS_EX_NOACTIVATE);
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

Add-Type -TypeDefinition $csharpCode -ReferencedAssemblies PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$window = New-Object NotificationWindow $WindowId
$window.Show()
[System.Windows.Threading.Dispatcher]::Run()

# 通知显示完成后，写入操作日志
$activityLogScript = Join-Path $scriptDirectory "..\activity\WriteActivityLog.ps1"
if (Test-Path $activityLogScript) {
    & powershell -ExecutionPolicy Bypass -File "$activityLogScript" -WindowId $WindowId -Action "完成通知"
}
