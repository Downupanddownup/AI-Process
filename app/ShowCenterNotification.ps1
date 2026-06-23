<#
.SYNOPSIS
    WPF 版屏幕边缘呼吸灯提示效果演示（支持入参）。

.DESCRIPTION
    使用 WPF + Grid 比例布局实现：全屏透明窗口 + 四边呼吸灯 + 中间偏上显示"X 号窗已完成"。
    支持 -WindowId 参数传入 1 或 2。
    不抢焦点、不中断输入、无声音，3 秒后自动淡出消失。

.PARAMETER WindowId
    窗口编号，1 或 2。
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("1", "2")]
    [string]$WindowId
)

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
        // 根布局：3 行（上边缘 / 中间 / 下边缘）
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

        // 顶部边缘条
        var topBar = CreateEdgeBar(edgeBrush, glowEffect);
        Grid.SetRow(topBar, 0);
        rootGrid.Children.Add(topBar);

        // 底部边缘条
        var bottomBar = CreateEdgeBar(edgeBrush, glowEffect);
        Grid.SetRow(bottomBar, 2);
        rootGrid.Children.Add(bottomBar);

        // 中间区域：3 列（左边缘 / 内容 / 右边缘）
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

        // 内容区：Canvas 比例定位，单个卡片靠近中央，两个同时显示时左右错开
        var contentCanvas = new Canvas {
            VerticalAlignment = VerticalAlignment.Stretch,
            HorizontalAlignment = HorizontalAlignment.Stretch
        };
        Grid.SetColumn(contentCanvas, 1);

        var card = CreateCard(windowNumber);
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

        // 呼吸动画
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

    private Border CreateCard(string number) {
        var card = new Border {
            Width = 460,
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

        var innerGrid = new Grid();
        innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Auto) });
        innerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // 左侧大号数字
        var numberBlock = new TextBlock {
            Text = number,
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

        // 右侧文字
        var textPanel = new StackPanel {
            Orientation = Orientation.Vertical,
            VerticalAlignment = System.Windows.VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 25, 0)
        };

        var line1 = new TextBlock {
            Text = "号窗",
            FontFamily = new FontFamily("Microsoft YaHei UI"),
            FontSize = 28,
            Foreground = new SolidColorBrush(Color.FromArgb(200, 255, 255, 255)),
            HorizontalAlignment = System.Windows.HorizontalAlignment.Left
        };
        var line2 = new TextBlock {
            Text = "已完成",
            FontFamily = new FontFamily("Microsoft YaHei UI"),
            FontSize = 28,
            Foreground = new SolidColorBrush(Color.FromArgb(200, 255, 255, 255)),
            HorizontalAlignment = System.Windows.HorizontalAlignment.Left
        };

        textPanel.Children.Add(line1);
        textPanel.Children.Add(line2);
        Grid.SetColumn(textPanel, 1);
        innerGrid.Children.Add(textPanel);

        card.Child = innerGrid;
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
        // 整体淡入
        var fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(300));
        BeginAnimation(UIElement.OpacityProperty, fadeIn);

        // 3 秒后淡出关闭
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
