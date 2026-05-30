# AI Process

`AI Process` 是一个基于 `AutoHotkey v2` 的 Windows 桌面快捷面板，用来减少和 AI 协作过程中的重复操作。

## 当前能力

1. `F2` 全局快捷键呼出窗口
2. 置顶小窗、托盘常驻、关闭隐藏到托盘
3. 设置当前主题目录
4. 创建 `需求.txt`
5. 根据当前目录中最新的 `vX.md` 创建 `对vX的回复.txt`
6. 复制需求提示词、回复提示词、文件关系说明
7. 可选“创建后用 IDEA 打开文件”
8. 提示词和快捷键通过配置文件集中维护

## 项目结构

```text
app/
  AIProcess.ahk
  config/
    settings.ini
  templates/
    requirement_prompt.txt
    reply_prompt.txt
    context_relation.txt
script/
  install.bat
  install.ps1
  uninstall.ps1
需求/
```

## 运行方式

1. 直接运行 [app/AIProcess.ahk](app/AIProcess.ahk)
2. 或执行 [script/install.bat](script/install.bat) 将程序注册到开始菜单
3. 安装后按 `Win` 键搜索 `AI Process` 启动

## 配置位置

应用配置在 [app/config/settings.ini](app/config/settings.ini)。

主要项：

1. `Hotkey`
2. `OpenWithIdea`
3. `IdeaCommand`
4. 窗口宽高与行为开关

提示词模板在 [app/templates](app/templates) 目录下，修改后重启程序即可生效。

## 需求文档

完整需求讨论、版本迭代和实施设计文档都保存在 [需求](需求) 目录中。
