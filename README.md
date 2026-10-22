# Auday（iOS + Apple Watch）

参考 [auday.ai](https://auday.ai) 实现的 iPhone + Apple Watch 全天 AI 录音记忆应用：**抬腕录音 → 设备端转写 → 健康 / 地点上下文 → AI 摘要、每日回顾与对话**。AI 模型可自定义（任意 OpenAI 兼容接口），界面支持中文 / 英文。

> An Auday-inspired iPhone + Apple Watch app: record from your wrist, transcribe on-device, enrich with health and place, then summarize, reflect and chat with any OpenAI-compatible model you bring.

## 功能

| 模块 | 说明 |
| --- | --- |
| ⌚️ Watch 录音 | 大按钮一键录音（支持双指互点手势），按 5 分钟分段，通过 `WCSession.transferFile` 自动同步到 iPhone（不在身边时排队，之后补传）。录音期间用体能训练会话保持后台运行并读取实时心率，结束后丢弃该训练、不写入「健身」。 |
| 📱 iPhone 录音 | 在「今天」页直接录音，支持后台录音和可配置的分段时长。 |
| 📝 设备端转写 | `SFSpeechRecognizer`，默认 `requiresOnDeviceRecognition`，支持简体中文 / English，句级时间戳；点击句子即可跳转播放。 |
| ❤️ 健康上下文 | HealthKit：心率（均值 / 区间 / 15 分钟曲线）、HRV → 压力估算、步数、活动能量、昨晚睡眠。每条录音标注平均心率和压力。 |
| 📍 地点 | 录音时反向地理编码当前地点。 |
| ✨ AI 摘要 / 高光 | 每条录音自动生成标题、摘要和高光时刻。 |
| 🌙 每日回顾 | 结合当天录音、健康和地点生成 Markdown 回顾。 |
| 💬 Ask Auday | 基于录音的流式对话（按日期 + 关键词检索相关录音），回答带 [R1] 引用，可跳转到原录音。Watch 上也可以口述提问，由 iPhone 回答。 |
| 🔍 时间线 & 搜索 | 按天浏览、全文搜索、标星、左滑删除、分享音频。 |
| ⌚️ 表盘复杂功能 | WidgetKit 圆形、矩形、角落和内联样式，轻点即开始录音（`auday://record`）。 |
| 🔒 隐私 | 没有服务器，也没有账号。音频只存在本机，只把**转写文本**直接发送到你配置的接口；API Key 存在钥匙串里。 |

## 自定义模型

设置 → AI 模型：选择预设，或选「Custom」填写任意兼容 `POST {baseURL}/chat/completions` 的服务。

| 预设 | Base URL | 默认模型 |
| --- | --- | --- |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| 通义千问 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` |
| Kimi | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-flash` |
| OpenRouter | `https://openrouter.ai/api/v1` | `openai/gpt-4o-mini` |
| Ollama（局域网） | `http://<电脑IP>:11434/v1` | `qwen2.5` |

页面里可以「获取模型列表」（`GET /models`）、调整温度，并「测试连接」。局域网 HTTP 地址已通过 `NSAllowsLocalNetworking` 放行。

## 构建

需要 macOS + Xcode 16 或更高版本，系统要求 iOS 18 / watchOS 11。

```bash
brew install xcodegen
xcodegen generate        # 生成 Auday.xcodeproj（以及 Config/ 下的 Info.plist 和 entitlements）
open Auday.xcodeproj
```

1. 在 `Auday`、`AudayWatch`、`AudayWidgets` 三个 target 中选择你的 Team（或者在 `project.yml` 里设置 `DEVELOPMENT_TEAM` 后重新生成）。
2. 如果需要，修改 `project.yml` 中的 Bundle ID 前缀 `com.mdongsheng`。
3. 运行 `Auday` scheme 到 iPhone 上，手表 App 会随之安装。HealthKit、语音识别和后台录音需要真机测试。

CI（`.github/workflows/build.yml`）会在 macOS 上为 iOS 和 watchOS 模拟器编译所有 target。

## 结构

```
project.yml            XcodeGen 工程定义（iOS App / Watch App / 复杂功能扩展）
Shared/                三端共用：Theme（设计规范）、WatchConnectivity 键名、Localizable.xcstrings
iOS/
  App/                 入口、Tab、AppSettings
  Models/              SwiftData 模型（Recording / TranscriptSegment / Highlight / DayReflection / ChatMessage）
  Recording/           iPhone 分段录音、播放器
  Ingest/              Watch 文件接收、处理队列（转写 → 健康 → 摘要）、后台任务
  Transcription/       SFSpeechRecognizer 封装
  Health/ Location/    HealthKit 快照、地点
  AI/                  OpenAI 兼容客户端（含 SSE 流式）、模型设置 / 钥匙串、Prompts、摘要 / 回顾 / 对话
  Views/               今天、时间线、详情、Ask、设置、引导页
Watch/                 录音（体能训练会话 + 心率）、WatchConnectivity、录音 / 提问 / 最近三页
Widgets/               watchOS 表盘复杂功能
```

## 说明

- 压力值是根据 HRV（SDNN）粗略估算的，不是医学指标。
- 没有服务器和账号，数据只保存在本机，卸载 App 会一并删除。
- 本项目受 Auday 启发，与 Auday 官方没有关联。
