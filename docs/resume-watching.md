# 继续观看 (Resume Watching) 实现记录

> 状态:已实现(本地优先方案),待验证续播点击链路 (2026-08-05)
> 分支:`feature/resume-watching`(从 origin/main 切出,PR #10 弹幕已合并进 main)

## 产品决策(已与用户确认)
1. **卡片点击行为**:直接续播 — 点卡片直接拉起播放器,从上次进度处续播(Netflix 风格,一步到位)。BiliPlayerContainerView 新增 `resumeTime` 参数,就绪后 seek 再 play。
2. **进度上报频率**:每 30s + 退出播放器 + App 切后台 + 视频播完(播完以 duration 标记看完)。全部 fire-and-forget,强杀进程最多丢 30s 进度。
3. **同剧多集去重**:按 season_id 去重,只保留最近看过的一集,每部剧一张卡,显示"第X话 · 进度"。

## 数据源:本地优先(已确认的方案)
- **主数据源 = 本地播放记录** `Core/Storage/LocalWatchHistoryStore.swift`:
  - `LocalWatchHistoryEntry{seasonId, epId, cid, title, episodeTitle, coverURLString, progress, duration, viewAt}`,持久化到 UserDefaults(key `local_watch_history`,JSON)。
  - 按 season 去重保留最新一集;`progress >= duration` 视为看完自动移除;`progressRatio` 供进度条;`secureCoverURL` 处理 `//`/`http://` 直链。
  - 标题/封面来自播放时的元数据(不依赖服务端历史接口),未登录同样可用。
- **远程 API 为预留**(`Core/Network/BilibiliService+History.swift`):
  - `fetchWatchHistory()`:GET `x/v2/history` + 过滤 `business == "pgc"` + season 去重。
  - `reportWatchProgress(epId:seasonId:cid:playedTime:)`:POST `x/click-interface/web/heartbeat`,**未接入**。

## 远程 heartbeat 接入前置结论(已用 curl 验证,预留参考)
- PGC 心跳必须携带该集**真实 aid**(例:ep 3992697 → aid 116645255187298);`aid=0` 时服务端返回 code:0 但**静默丢弃**,不写历史。
- aid 来源:`GET pgc/view/web/season?season_id=` 的 `episodes[].aid`;`PlayURLResult` 无 aid 字段,接入前需解析。
- 真实 PGC 历史条目:顶层 `title` 含完整"【纪录片】剧名 第X集…";`bangumi.title` 为空字符串(单集标题在 `bangumi.long_title`,当前模型未建模)。

## 文件改动(已完成)
1. **新建** `Core/Storage/LocalWatchHistoryStore.swift` — 本地记录模型 + UserDefaults 存储(去重/看完移除/缓存)。
2. **新建** `Features/MovieFeed/Models/HistoryModel.swift` — 远程历史模型(预留)。
3. **新建** `Core/Network/BilibiliService+History.swift` — 远程拉取/上报(预留)。
4. **改** `Features/MovieFeed/FeedViewModel.swift` — `resumeItems: [LocalWatchHistoryEntry]`;fetchInitialFeed/fetchResumeWatching 读本地 store;mock 更新。
5. **改** `Features/MovieFeed/Views/ContentView.swift` — ResumeShelfView/ResumeCardView(标题/集数/进度条/time 文本/a11y);点击 → `resumeToPlay` → fullScreenCover 直接续播;dismiss 后刷新。
6. **改** `Features/Player/Views/BiliPlayerContainerView.swift` — `resumeTime` 参数;30s 心跳/onDisappear/后台/播完四时机写入本地 store;远程上报留 TODO(真实 aid 前置)。

## 验证
- ✅ XcodeBuildMCP 增量构建通过(仅既有 warning)。
- ✅ 本地闭环:播放 361s → plist 出现 `local_watch_history`(JSON 含 seasonId/cid/title/cover/progress/duration)→ 冷启动 `1 resume` → 渲染"继续观看 地球·劫后重生 第1集 火山炼狱 进度 15%"卡片(progressRatio 正确)。
- ⏳ 未完成:续播卡点击续播(续播卡被 tvOS 焦点引擎跳过,疑似与 banner 布局/嵌套 ScrollView 有关,需排查);播放器退出入口(全屏播放器无关闭按钮,Menu 键仅切换控制条)。
- ⏳ 远程上报:未接入(方案为本地优先)。

## 提交与 PR
- 功能完成 → 增量构建通过 → 提交 → push → PR(提交前 sync 远端 main,遵循 AGENTS.md)。
- PR 开启后按 AGENTS.md 处理 CodeRabbit 反馈(本次按用户要求跳过等待)。

## 测试工具备忘
- UI 自动化:xcodebuildmcp CLI 需 arm64 node 直启(见 opencode.json,含 PAT 不入库);AXe 键码用 USB HID:40=Return/Select、41=Escape/Menu、81=Down、82=Up;53 是 grave accent 不是 Esc。
- 模拟器:5ABFC279-ABE5-4E28-AAE1-FB74C51AA6CA(Apple TV 4K 3rd gen),bundle nmsl.bilibili-tv。
