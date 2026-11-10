<div align="center">

<img src="docs/images/banner.jpg" alt="Smart Cooler Control Banner" width="100%" style="border-radius: 12px; margin-bottom: 16px;">

# Smart Cooler Control for MacBook (苹果电脑智能散热器控制)

**专为搭载 Apple Silicon 芯片的 MacBook 设计的智能多品牌主动半导体制冷散热器控制系统。**  
*专为大功率外置磁吸半导体（Peltier/TEC）散热器（≥ 30W）深度优化，彻底消除高负载发热降频，释放 M 系列芯片持久峰值性能。*

[English](README.md) • [Português (Brasil)](README.pt-BR.md) • [简体中文](README.zh-CN.md)

<br/>

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B%20Ventura%20%7C%20Sonoma%20%7C%20Sequoia-blue?logo=apple)](docs/GETTING_STARTED.md#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%20%7C%20M2%20%7C%20M3%20%7C%20M4%20%7C%20M5-black?logo=apple)](docs/GETTING_STARTED.md#requirements)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B%20%7C%20AppKit%20%2B%20CoreBluetooth-orange?logo=swift)](docs/DEVELOPMENT.md)
[![硬件标准](https://img.shields.io/badge/%E6%95%A3%E7%83%AD%E6%A0%87%E5%87%86-%E2%89%A5%2030W%20%E5%A4%A7%E5%8A%9F%E7%8E%87%E5%8D%8A%E5%AF%BC%E4%BD%93-red?logo=target)](docs/COMPATIBILITY.md)
[![开源许可: MIT](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-MIT-green.svg)](LICENSE)

</div>

---

## ⚡ 为什么需要 Smart Cooler Control？

搭载 Apple Silicon 芯片（**M1、M2、M3、M4，涵盖标准版、Pro、Max、Ultra 以及无风扇 MacBook Air**）的 Mac 拥有极高能效比。但在持续高负载场景下——如 **8K ProRes 视频渲染导出、Blender/Cinema 4D 三维渲染、本地大语言模型推理（Ollama、LM Studio）、Xcode 大型项目编译以及高画质游戏**，铝合金机身会快速积热，导致芯片保护性降频，性能断崖式下跌。

市面上常见的 **10W 至 15W** 便携式手机散热背夹，制冷量根本无法穿透 MacBook 厚实的实心铝合金外壳。

**Smart Cooler Control 确立了严苛的发烧级标准：≥ 30W。** 释放配备液冷均热板（Vapor Chamber）、大面积定制半导体制冷片（TEC）与高达 9,000 转高速离心涡轮风扇的真正冷却潜力，通过 macOS 原生蓝牙低功耗（BLE）进行毫秒级直连调控。

---

## 📸 软件界面预览

<div align="center">
<table>
  <tr>
    <td align="center" width="25%">
      <img src="docs/images/screenshot_auto_smartmax.png" alt="Smart Max 极速制冷模式" width="100%"/>
      <br/><b>Smart Max 极速模式</b><br/>
      <sub>达到阈值瞬时爆发 100% 制冷</sub>
    </td>
    <td align="center" width="25%">
      <img src="docs/images/screenshot_auto_balanced.png" alt="Balanced 均衡温控模式" width="100%"/>
      <br/><b>Balanced 均衡模式</b><br/>
      <sub>随核心温度平滑声学曲线升降速</sub>
    </td>
    <td align="center" width="25%">
      <img src="docs/images/screenshot_manual.png" alt="Manual 手动精准模式" width="100%"/>
      <br/><b>Manual 手动档位模式</b><br/>
      <sub>滑块、定时器与全彩灯效控制</sub>
    </td>
    <td align="center" width="25%">
      <img src="docs/images/screenshot_device_picker.png" alt="多品牌设备发现" width="100%"/>
      <br/><b>多品牌设备发现</b><br/>
      <sub>≥ 30W 专属蓝牙驱动隔离名录</sub>
    </td>
  </tr>
</table>
</div>

---

## 🚀 核心功能亮点

### 🧠 双模智能温控自动巡航 (Thermal Autopilot)
- **Smart Max (极速性能模式)：** 平常以静音最低功耗（`[40%] [60%] [80%] [100%]`）维持基准冷却；一旦核心温度达到设定的**介入阈值**（如 $\ge 50^\circ\text{C}$），瞬间开启 100% 满血功率暴力散热。
- **Balanced (均衡平滑模式)：** 低温时保持基准静音转速；一旦超过介入温度，风扇转速随温度平滑线性爬升，兼顾极致散热与低噪体验。

### ❄️ 主动防冷凝水与结霜保护 (Anti-Condensation)
- 36W 至 40W 的大功率半导体制冷片在低负载或电脑低温时可能使接触面降至冰点以下（$< 0^\circ\text{C}$），引发空气中水汽结露。
- 软件内置**关断阈值 (Shutoff Threshold)**（如 $< 38^\circ\text{C}$），在 Mac 降温后自动将散热器置于待机关机状态（0% 转速与断电保护）。
- 滑块完全解耦独立：调节关断温度绝不会错误拖拽或干扰启动温度。

### ⚙️ 契合硬件电机物理特性的档位划分 (MIN POWER)
- 9,000 转高速无刷风机在低于 40% PWM 占空比时因磁阻力无法正常平稳转动。
- 彻底摒弃误导性的 20% 与 30% 虚拟档位，采用与官方红魔 Goper 原厂一致且每一档均具有明显风量与转速递进的真实档位：**`[40%] [60%] [80%] [100%]`**。

### 🌈 适配 Mac 全系机型的智能温控氛围灯
- 散热器 RGB 随芯片真实发热区间智能变色：**翡翠绿**（低温待机） $\rightarrow$ **暖黄/琥珀色**（中度负载） $\rightarrow$ **警示鲜红**（高温过热/降频保护）。
- 针对 Apple Silicon 机型定制专属温控曲线：
  - **MacBook Air:** 针对无风扇机身散热特性调校（$35^\circ\text{C}\dots55^\circ\text{C}$ 绿灯，$>80^\circ\text{C}$ 红灯）。
  - **MacBook Pro:** 结合内置双风扇工作机制调校（$38^\circ\text{C}\dots58^\circ\text{C}$ 绿灯，$>82^\circ\text{C}$ 红灯）。
  - **Mac Studio / Mac mini / Mac Pro:** 针对台式机厚散热鳍片调校（$30^\circ\text{C}\dots50^\circ\text{C}$ 绿灯，$>72^\circ\text{C}$ 红灯）。

### 🛡️ 原生深入 macOS 系统电源生命周期
- 完美监听 macOS `NSWorkspace` 生命周期：Mac 睡眠合盖（`willSleepNotification`）或关机（`willPowerOffNotification`）时立即自动关闭散热器，唤醒亮屏（`didWakeNotification`）时自动恢复智控。
- 启动静默后台自动回连。

---

## 🔌 支持的大功率散热器名录 (≥ 30W 标准)

具备严格的驱动隔离机制，各品牌使用专属 GATT 特征协议，彻底杜绝数据包误发：

| 品牌 | 型号 | 额定峰值功率 | 架构与散热技术 | 适配状态 |
| :--- | :--- | :---: | :--- | :---: |
| **红魔 (REDMAGIC)** | **散热器 6 Pro+** | **40W** | 液冷均热板 VC + 超频大半导体 | ✅ 原生驱动支持 |
| **红魔 (REDMAGIC)** | **磁吸散热器 5 Pro** | **36W** | 3D 立体 VC 均热板 + 9000 转风机 | ✅ 硬件真机实测完美 |
| **红魔 (REDMAGIC)** | **VC 散热器 6 Pro** | **36W** | 均热板 VC + 定制大半导体 | ✅ 硬件真机实测完美 |
| **红魔 (REDMAGIC)** | **低温散热器 8 Pro** | **36W** | 第四代定制超导冷冻 TEC | ✅ 原生驱动支持 |
| **红魔 (REDMAGIC)** | **散热器 4 Pro** | **27W** | 大功率磁吸半导体 | ✅ 原生驱动支持 |
| **黑鲨 (Black Shark)** | **磁吸散热背夹 5 Pro** | **35W** | 5 档定制 TEC (5100 RPM) | ✅ 原生驱动支持 |
| **黑鲨 (Black Shark)** | **磁吸散热器 4 Pro** | **27W** | 双路供电与风量控制 | ✅ 原生驱动支持 |
| **飞智 (Flydigi)** | **飞智 B8X** | **30W** | 超频变频制冷片 | ✅ 原生驱动支持 |
| **飞智 (Flydigi)** | **飞智 B7X** | **27W** | 变频控温磁吸散热背夹 | ✅ 原生驱动支持 |
| **美莫 (MEMO)** | **CX08 / CX07** | **30W–36W** | 大功率电竞磁吸散热器 | ✅ 原生驱动支持 |
| **iQOO** | **散热背夹 2 Pro** | **27W–33W** | 双半导体制冷片双夹具 | 🔄 协议解析提取中 |
| **一加 (OnePlus)** | **45W 液冷散热背夹** | **45W** | 外置水冷泵箱 + 半导体 | 🔄 协议解析提取中 |

---

## 🛠️ 安装与编译指南

### 系统要求
- macOS 13.0 (Ventura)、macOS 14.0 (Sonoma)、macOS 15.0 (Sequoia) 或更高版本。
- 搭载 Apple Silicon 芯片的 Mac 电脑（`arm64` 架构：M1、M2、M3、M4、M5，包含标准版、Pro、Max、Ultra）。
- 已开启蓝牙并授予蓝牙权限。

### 本地源码编译
```bash
# 克隆仓库
git clone https://github.com/Despensativo/redmagic-cooler-mac.git
cd redmagic-cooler-mac

# 编译并自动安装至 /Applications 目录
./build.sh --run
```
编译脚本将自动输出完全独立无外部臃肿依赖的 `/Applications/Smart Cooler Control.app`。

---

## 🏷️ 关键词与索引标签 (SEO)

`mac-cooler` • `macbook-cooling` • `apple-silicon` • `macbook-pro-m3` • `macbook-air-m2` • `thermal-throttling` • `redmagic-mac` • `redmagic-cooler-5pro` • `vc-cooler-6-pro` • `black-shark-cooler` • `flydigi-b8x` • `peltier-cooling` • `半导体制冷` • `红魔散热器mac` • `黑鲨散热器mac` • `飞智b8x` • `mac状态栏应用` • `swift-macos`

---

## 🤖 散热器未响应或暂未支持？AI 辅助修复与问题反馈

由于各品牌蓝牙散热器在不同批次或固件版本中可能会更改广播名称或 GATT 特征 UUID，您的散热器可能会出现连接后不响应或暂未被识别的情况。

您可以直接使用任意 AI 模型（**Claude、ChatGPT、Gemini、Cursor 或 Antigravity**）快速分析日志并提取修复方案：

### 1. 获取本地蓝牙诊断日志
在软件中扫描或连接您的散热器后，打开终端（Terminal）运行以下命令获取最近 50 行日志：
```bash
tail -n 50 ~/.cooler.log
```

### 2. 复制以下提示词（Prompt）发送给 AI 助手
```text
我正在使用 macOS 开源项目 "Smart Cooler Control" (https://github.com/Despensativo/redmagic-cooler-mac)。
我的蓝牙散热器目前无法正常响应或尚未被识别。

项目架构背景：
- 设备配置与蓝牙匹配规则位于 `src-swift/BLE/DeviceProfile.swift`。
- 各品牌独立 GATT 驱动位于 `src-swift/BLE/Drivers/`（`RedMagicDriver.swift`、`BlackSharkDriver.swift`、`FlydigiDriver.swift`、`MemoDriver.swift`、`OnePlusDriver.swift`、`IQOODriver.swift`）。
- 修改代码后可通过 `./build.sh --run` 直接编译并运行测试。

以下是我的散热器型号与 `~/.cooler.log` 日志内容：
- 散热器品牌与型号：[填写品牌、型号及功率]
- 遇到的现象：[例如：扫描不到 / 连接成功但风扇不转 / 灯光无法调节]
- 日志输出 (`~/.cooler.log`)：
[在此粘贴 tail -n 50 ~/.cooler.log 的输出内容]

请你：
1. 分析日志中的 BLE 广播名称、Service UUID、Characteristic UUID 以及原始十六进制数据包。
2. 找出原因并给出 `DeviceProfile.swift` 及对应驱动的具体 Swift 修改代码，方便我通过 `./build.sh --run` 本地验证。
3. 生成一份结构化的【技术诊断摘要】（包含广播名、UUID 列表、指令格式与代码 Diff），以便我发送给项目维护者合并更新。
```

### 3. 提交报告或发送邮件，帮助我们更新官方版本！
无论您通过 AI 成功验证了修复方案，还是仅希望提交诊断日志由我们协助适配，欢迎通过以下方式联系：
- 📧 **发送邮件：** [despensativo@gmail.com](mailto:despensativo@gmail.com?subject=Smart%20Cooler%20Control%20-%20Device%20Report%20%2F%20Fix)
- 🐛 **GitHub Issues / PR：** [提交 Issue 或 Pull Request](https://github.com/Despensativo/redmagic-cooler-mac/issues)

收到您的反馈后，我们将第一时间完成适配并合并至下一版官方更新中！

---

## 🙏 致谢与声明

**Smart Cooler Control** 是一个全新的独立多品牌大功率（≥ 30W）半导体制冷管理平台。特别感谢 [@hajarrashidi](https://github.com/hajarrashidi/redmagic-cooler-mac) 早期针对单款红魔 6 Pro 散热器提供的基础项目启发。

---

## 📄 开源许可证

本项目基于 [MIT 许可证](LICENSE) 开放源代码。
