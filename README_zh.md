# BiliTV - Apple TV 第三方 Bilibili 客户端

![BiliTV Hero Banner](/Users/debiancc/.gemini/antigravity/brain/a96ddd1f-bf21-4bc2-bb98-d6f77885cd09/bilitv_hero_banner_1776492163738.png)

一个专为 Apple TV 设计的第三方 Bilibili 客户端，旨在提供极致的大屏观影体验。

## 🌟 核心目标

本项目的主要目标是为 **Bilibili 大会员** 用户提供便捷、高清的影视资源播放支持。针对 Apple TV 的硬件性能，优化解码与渲染，让您在电视上也能畅享 4K、杜比视界等高画质内容。

## ✨ 主要特性

- 📺 **Apple TV 原生体验**：完全基于 SwiftUI 构建，完美适配 Siri Remote 遥控器操作，交互流畅自然。
- 🎬 **电影 Feed 流**：已实现电影频道 Feed 流接入，支持瀑布流展示与无限加载。
- 💎 **大会员专享优化**：深度集成大会员权益，优先支持影视资源的高清、无损播放。
- 🚀 **极致画质**：支持最高 4K 分辨率、1080P 60帧、杜比音效及多音轨切换。
- 🧼 **简洁界面**：剔除一切广告与社交冗余，回归观影本质。
- 🔄 **云端同步**：支持播放记录同步、稍后再看（开发中），跨设备无缝衔接。

## 🛠 技术栈

- **UI 框架**: SwiftUI
- **数据持久化**: SwiftData
- **网络层**: URLSession / Combine
- **视频引擎**: AVKit (支持原理解码)
- **平台**: tvOS 26.0+
- **开发语言**: Swift 6.2+ (Swift tools 6.2)

## 🚀 快速开始

### 前置要求
- 一台安装了 macOS 的电脑
- 最新版本的 Xcode
- 苹果开发者账号（用于真机部署）

### 安装步骤
1. 克隆本项目：
   ```bash
   git clone https://github.com/your-repo/bilibili_tv.git
   ```
2. 使用 Xcode 打开 `bilibili_tv.xcodeproj`。
3. 在项目设置中配置你的 **Development Team**。
4. 选择你的 Apple TV 设备或模拟器作为运行目标。
5. 按下 `Cmd + R` 编译并运行。

## 📸 预览 (预览图生成中)
*即将上线更多功能截图...*

## 📝 免责声明

1. 本软件为开源第三方客户端，仅供个人学习与技术交流使用，严禁用于商业用途。
2. 本软件不直接提供任何视频内容，所有内容均来源于 Bilibili 官方接口。
3. 视频版权归 Bilibili 及其相关权利人所有，使用本软件请遵守相关法律法规及 Bilibili 用户协议。

---

> [!TIP]
> 如果你喜欢这个项目，欢迎点个 Star 🌟 或者提交 Pull Request 来完善它！
