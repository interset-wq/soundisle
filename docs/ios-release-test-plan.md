# MusicDL iOS 正式版测试要点

> 适用范围：`go-music-dl` iOS 包（v1.1.5 基线，commit `c445ddd`，2026-11-09）
> 测试范围：**仅 iOS**。按本次要求，Android 正式版测试跳过，不在本文档内展开。
> 文档状态：待执行。文中“预期”是判定标准，不代表已经通过。

## 0. 结论先行

- 当前这台 Ubuntu 主机没有 USB-C，无法连接 iPad；也没有 macOS/Xcode，无法完成 iOS 签名、安装和真机验证。
- 因此本文档只负责给出**可执行的测试要点、判定标准、证据要求和交接方式**。
- 真机执行需要交给具备 **macOS + Xcode + iPad** 的 Agent 完成，交接提示词见 `ios-test-handoff.md`。
- 本机可以先做的只有：IPA 校验和、ZIP 结构、Info.plist、静态代码/配置检查（见附录 A）。

## 1. 被测对象

| 项目 | 值 |
| --- | --- |
| 源码基线 | `tmp/go-music-dl`，tag `v1.1.5`，commit `c445ddd` |
| 签名包 | `music-dl-ios.ipa` + `music-dl-ios.ipa.sha256` |
| 未签名包 | `music-dl-ios-unsigned.ipa` + `.sha256`（**不能直接安装，必须重签**） |
| 默认 Bundle ID | `com.guohuiyuan.musicdl` |
| 最低系统 | iOS 13（脚本默认 `IOS_MIN_SDK=13`） |
| 架构 | arm64 |
| 应用内服务 | `http://127.0.0.1:37777/music/`，健康检查 `/music/healthz` |
| 数据文件 | App 数据目录下 `settings.db`、`cookies.json`；默认下载目录为相对路径 `data/downloads`（iOS 可写性待验证） |
| 前端资源 | APlayer、FontAwesome、Sakana 已内置，不依赖 jsDelivr |
| 桌面模式鉴权 | 关闭（`StartDesktop` 使用 `DisableAuth: true`） |

执行前必须记录实际产物值，不能只抄上表：

- `CFBundleShortVersionString`
- `CFBundleVersion`
- IPA 的 SHA256
- 设备型号、iPadOS 版本、安装方式（直接侧载 / SideStore / AltStore / LiveContainer）

## 2. 高风险点（静态检查发现，优先验证）

| 编号 | 风险 | 为什么重要 | 对应用例 |
| --- | --- | --- | --- |
| R1 | 仓库内未发现 `UIBackgroundModes=audio` / `AVAudioSession` 配置 | WKWebView 音频进入后台可能被系统挂起，锁屏播放/控制中心可能不可用；这是音乐 App 的核心能力 | D01、D02、D16、D20 |
| R2 | “浏览器下载”在 iOS 上通过系统浏览器打开 `127.0.0.1` 下载地址 | App 进入后台后内置服务可能被挂起，Safari 可能报“无法连接服务器” | C09 |
| R3 | 未发现 `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` | 下载文件可能只能在本 App 的“本地音乐”里看到，无法在“文件”App 中直接取用 | C07、C09、D13 |
| R4 | 文件夹导入使用 `webkitdirectory` | iPadOS 的文件选择器对目录选择支持不完整，可能只能选文件或直接无响应 | C10、D12 |
| R5 | `app.js` 大量使用可选链 `?.`，最低系统却标为 iOS 13 | 可选链需要 iOS 13.4+；iOS 13.0–13.3 可能整段脚本语法错误，表现为白屏 | A03、B01、F01 |
| R6 | iOS CI 的 `IOS_VERSION` 固定为 `1.0.0.1`，应用版本是 `1.1.5` | 发布页版本号、应用内版本、崩溃报告可能对不上 | A09 |
| R7 | iOS 专用 ATS/本地网络配置只存在于打包脚本 | 重签或手工改包后容易丢失，导致 HTTP 资源加载失败 | A04、D09 |
| R8 | 移动端“打开下载目录”明确返回不支持 | 用户可能认为下载失败；需要确认提示文案和替代路径 | C14 |
| R9 | 默认下载目录是相对路径 `data/downloads` | iOS 进程的工作目录可能是只读的 App Bundle，相对路径可能写入失败；需要确认实际写入位置 | C07、C08、C12 |
| R10 | “保存到本地目录”使用 `target="_blank"` + `Content-Disposition: attachment` | WKWebView 对 `target="_blank"` 和附件下载的处理与桌面浏览器不同，可能无响应或停留在空白页 | C07、C09 |

## 3. 测试环境与准入条件

### 3.1 必须满足

- macOS 15+，Xcode 16+（或与 CI `macos-15` 一致），安装 Command Line Tools。
- 真机 iPad（arm64），至少一台现代机型；建议再准备一台旧机型或旧系统。
- 签名方式二选一：
  - 开发者账号 + 包含测试设备 UDID 的 provisioning profile，Bundle ID 与包一致；
  - 使用 SideStore / AltStore / 其他重签工具对 `music-dl-ios-unsigned.ipa` 重签后安装。
- iPad 与 Mac 可连接（USB-C 或同一 Wi-Fi 的调试方式均可）。
- 测试网络：Wi-Fi、蜂窝、可切换的代理/弱网；准备一首可播放的测试歌曲。
- 工具：Xcode Devices、Console.app、Safari Web Inspector、屏幕录制、Files App。
- 测试数据：至少 3 个来源的歌曲、1 个长歌单（100+ 首）、1 个本地音频文件、1 个非音频文件（用于异常导入）。

### 3.2 基线重置

每个大轮次开始前：

1. 卸载 App，确认数据被清除；
2. 重新安装，首次启动完成；
3. 记录设备剩余空间、系统版本、网络环境；
4. 清空 Safari 下载记录和 Files 中的旧测试文件。

### 3.3 严重级别

- **P0 阻断**：无法安装/启动、白屏、闪退、核心播放/下载不可用、数据丢失、局域网暴露服务。
- **P1 严重**：后台播放、锁屏控制、恢复前台、本地导入/导出等 iOS 核心体验失败；主流渠道不可用。
- **P2 一般**：布局、安全区、深色模式、文案、边缘机型兼容。

## 4. 执行顺序与时间盒

| 批次 | 内容 | 预计 | 不通过时 |
| --- | --- | --- | --- |
| Gate | A 产物/安装 + B 启动冒烟 | 30–45 分钟 | 立即停止，先修安装/启动 |
| Smoke | C 核心链路 | 60–90 分钟 | 阻断项修完再继续 |
| Platform | D iOS 专项 | 2–3 小时 | 记录后继续，除非 P0 |
| Matrix | E 渠道矩阵 | 1.5–2 小时 | 可抽样，P0 渠道必须全跑 |
| Soak | D20 长稳 + 回归 | 1 小时 | 发布前必须完成 |

## 5. 测试用例

### A. 产物与安装（Gate）

| ID | 优先级 | 测试点 | 操作与判定 |
| --- | --- | --- | --- |
| IOS-A01 | P0 | 校验和 | `shasum -a 256 -c *.sha256` 通过；SHA256 与发布页/交接单一致 |
| IOS-A02 | P0 | IPA 完整性 | `unzip -tq` 无错误；存在 `Payload/MusicDL.app/Info.plist` 和可执行文件 `MusicDL` |
| IOS-A03 | P0 | 包元数据 | `CFBundlePackageType=APPL`；`MinimumOSVersion` 与声明一致；`lipo -archs` 含 `arm64` |
| IOS-A04 | P0 | ATS/本地网络 | `NSAllowsLocalNetworking=true`、`NSAllowsArbitraryLoadsInWebContent=true`、`NSLocalNetworkUsageDescription` 非空 |
| IOS-A05 | P0 | 签名与描述文件 | `codesign --verify --deep --strict` 通过；profile 未过期、Team/Bundle ID 匹配、包含测试设备 UDID |
| IOS-A06 | P0 | 安装 | 直接侧载安装成功，桌面出现 MusicDL 图标；不出现 “invalid format” |
| IOS-A07 | P0 | 未签名包流程 | 未签名 IPA 直接安装应失败（预期）；重签后可安装，重签步骤可复现 |
| IOS-A08 | P0 | 首次启动数据 | 启动后生成 `settings.db`；登录或保存 Cookie 后生成 `cookies.json`；桌面模式不要求 setup token |
| IOS-A09 | P1 | 版本一致性 | 应用内/系统设置/崩溃报告中的版本与发布版本一致；若仍显示 1.0.0.x，记为发布元数据问题 |
| IOS-A10 | P1 | 重装 | 卸载后重装可正常启动；旧数据不残留；重装后权限提示重新出现 |

### B. 启动与稳定性（Gate / 冒烟）

| ID | 优先级 | 测试点 | 操作与判定 |
| --- | --- | --- | --- |
| IOS-B01 | P0 | 冷启动 | 双击图标到首页可交互 ≤ 10 秒；无白屏、无闪退 |
| IOS-B02 | P1 | 内置服务 | 通过 Safari Web Inspector 的 Network 或 App 内请求确认 `/music/healthz` 返回 2xx；若用 Safari 直接访问，App 切后台可能被挂起，失败单独记录不直接判 P0 |
| IOS-B03 | P0 | 桥接确认 | 首页正常渲染；Console 无 “bridge” 相关无限重试；地址栏/日志显示已注入桥接 |
| IOS-B04 | P1 | 启动诊断页 | 连续导航失败后出现诊断页，页面包含目标地址/尝试次数/运行环境；不出现无限刷新。无法模拟时记 N/A，并附源码位置 |
| IOS-B05 | P0 | 前后台切换 | 连续 10 次“后台 30 秒 → 回前台”，每次均能恢复画面，无白屏、无重新加载丢搜索结果 |
| IOS-B06 | P0 | 暂停状态恢复 | 停在搜索结果页 → 后台 1 分钟 → 回前台；页面内容和 URL 保持；若触发重载，应回到原页面而非首页 |
| IOS-B07 | P1 | 播放状态恢复 | 播放中后台 1 分钟再回前台；播放不断；若原生层空白，重载应延后到暂停后 |
| IOS-B08 | P1 | 旋转 | 竖屏/横屏来回切换 5 次；布局、播放器、弹窗不重叠、不被裁切 |
| IOS-B09 | P1 | 安全区 | 刘海/圆角/底部 Home 指示条不遮挡顶部按钮、底部播放器和输入框 |
| IOS-B10 | P2 | 深色模式 | 系统深色/浅色切换；文字、图标、弹窗、播放器可读 |
| IOS-B11 | P1 | 空闲稳定 | 首页/搜索结果停留 30 分钟；无闪退、无明显内存暴涨、无持续 CPU 占用 |
| IOS-B12 | P1 | 崩溃收集 | 若闪退，能取到“设置 → 隐私与安全 → 分析与改进 → 分析数据”对应报告并附到问题单 |

### C. 核心功能（冒烟，P0 除注明外）

| ID | 优先级 | 测试点 | 操作与判定 |
| --- | --- | --- | --- |
| IOS-C01 | P0 | 单源搜索 | 选网易云/QQ 各搜一首歌；结果、封面、歌名、歌手正常；无“搜索为空”误报 |
| IOS-C02 | P0 | 多源聚合 | 同时选 3 个来源搜索；结果可去重/换源；切换来源不丢当前输入 |
| IOS-C03 | P0 | 内置资源 | 阻断 jsDelivr/CDN（或弱网）后冷启动；播放器样式、图标字体、Sakana 仍正常 |
| IOS-C04 | P0 | 播放控制 | 播放/暂停/拖动进度/上一首/下一首/音量/倍速均生效；进度与音频同步 |
| IOS-C05 | P1 | 歌词 | 打开歌词，逐字/普通歌词滚动正常；切换歌词字体后重启仍保留 |
| IOS-C06 | P1 | 队列/歌单 | 播放全部、加入队列、随机/循环、删除队列项均生效；长列表滚动不卡死 |
| IOS-C07 | P0 | 应用内下载 | 单曲下载进度正常；完成后在“本地音乐”可见并可播放；记录文件实际写入路径（核对是否可写、是否在 App 容器内） |
| IOS-C08 | P1 | 批量下载 | 3–5 首批量下载；队列串行/并发符合预期；重复下载有去重提示 |
| IOS-C09 | P0 | 浏览器下载 | 点“浏览器下载”应打开 Safari/Files 并完成下载；若因 App 后台导致无法连接，按 R2 记 P1/P0 |
| IOS-C10 | P1 | 本地导入 | 从 Files 选择单个/多个音频导入成功；尝试文件夹导入并记录是否支持 |
| IOS-C11 | P1 | 本地音乐 | 本地歌曲可播放、封面/歌词正常；删除后列表和磁盘同步 |
| IOS-C12 | P0 | 设置持久化 | 修改下载目录、文件名模板、歌词选项后强制退出再启动；设置保留且下载生效 |
| IOS-C13 | P1 | 登录 | Cookie 导入/扫码登录（如可用）成功后能看个人歌单；重启后 Cookie 仍在；退出登录生效 |
| IOS-C14 | P1 | 打开下载目录 | 点“打开下载目录”应给出明确“iOS 不支持”提示，不闪退、不白屏 |
| IOS-C15 | P2 | WebDAV | 配置 WebDAV 后下载同步成功；错误地址/密码有明确错误提示 |
| IOS-C16 | P2 | AI 控制接口 | 在 iPad Safari 打开 `127.0.0.1:37777` 的 AI 索引；播放器在线时 `GET /api/ai/player/state` 有真实状态 |

### D. iOS 平台专项

| ID | 优先级 | 测试点 | 操作与判定 |
| --- | --- | --- | --- |
| IOS-D01 | P0 | 后台播放 | 播放后锁屏/回桌面，等待 10 分钟；音频持续，通知栏/锁屏有播放状态 |
| IOS-D02 | P0 | 锁屏控制 | 锁屏/控制中心显示歌名、歌手、进度；播放/暂停/上一首/下一首/拖动进度可用 |
| IOS-D03 | P0 | 音频打断 | 来电/FaceTime、闹钟、Siri、其他 App 播放、拔耳机；恢复后状态合理，不出现双播/静音死锁 |
| IOS-D04 | P1 | 输出路由 | AirPods/蓝牙音箱/AirPlay 切换；声音跟随路由，切回扬声器正常 |
| IOS-D05 | P0 | 长时间后台恢复 | 播放/暂停两种状态各后台 10 分钟再回前台；不白屏、不丢当前页、不重复叠音 |
| IOS-D06 | P1 | 后台下载 | 下载中锁屏/切后台 5 分钟；返回后进度连续，失败可重试；记录 iOS 是否暂停下载 |
| IOS-D07 | P1 | 网络切换 | Wi-Fi ↔ 蜂窝 ↔ 飞行模式；播放自动恢复或给出可重试错误，不永久卡加载 |
| IOS-D08 | P1 | 本地网络权限 | 首次启动观察是否弹权限；允许/拒绝/在设置中改回；拒绝后页面有可理解提示 |
| IOS-D09 | P0 | HTTP/HTTPS 混用 | 分别播放 HTTP 与 HTTPS 音频源；不被 ATS 拦截；封面/歌词同样可加载 |
| IOS-D10 | P1 | 分屏/台前调度 | iPad 分屏或 Stage Manager 下调整窗口大小；布局自适应，播放器不被裁切 |
| IOS-D11 | P1 | 键盘/输入 | 外接键盘或软键盘输入搜索词；粘贴、长按选择、回车搜索正常；键盘不遮挡结果 |
| IOS-D12 | P1 | 文件选择器 | 从“iCloud 云盘”和“我的 iPad”分别导入；取消选择不报错；大文件有进度 |
| IOS-D13 | P2 | 分享/导出 | 对已下载文件尝试分享/存储到“文件”；若产品未提供入口，记录为 R3 产品缺口 |
| IOS-D14 | P2 | 低电量/发热 | 低电量模式播放 30 分钟；无异常中断；设备发热可接受 |
| IOS-D15 | P1 | 长列表内存 | 500+ 首歌单连续滚动、搜索、播放；无 OOM/闪退，滚动帧率可接受 |
| IOS-D16 | P1 | 锁屏解锁 | 播放中锁屏 5 分钟再解锁；App 回到原页面，播放状态与控制按钮一致 |
| IOS-D17 | P0 | 覆盖升级 | 旧版本安装并产生数据后覆盖安装新包；设置、Cookie、下载记录保留，能正常启动 |
| IOS-D18 | P1 | 无障碍 | VoiceOver 能读出主要按钮；点击区域不小于约 44×44pt；动态字体不破坏布局 |
| IOS-D19 | P0 | 局域网暴露 | 同一 Wi-Fi 下从另一台设备访问 `http://<iPad-IP>:37777/music/healthz`；应连接失败/拒绝 |
| IOS-D20 | P1 | 1 小时长稳 | 连续播放/切歌/搜索 1 小时；无闪退、无内存持续增长、无音频中断；记录耗电 |

### E. 渠道矩阵（每个来源至少 1 首）

| ID | 来源 | 搜索 | 播放 | 下载 | 歌词 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| IOS-E01 | 网易云 `netease` | ☐ | ☐ | ☐ | ☐ | FLAC/无损可用 |
| IOS-E02 | QQ `qq` | ☐ | ☐ | ☐ | ☐ | FLAC/无损可用 |
| IOS-E03 | 酷狗 `kugou` | ☐ | ☐ | ☐ | ☐ | 普通歌曲 FLAC |
| IOS-E04 | 酷我 `kuwo` | ☐ | ☐ | ☐ | ☐ | |
| IOS-E05 | 咪咕 `migu` | ☐ | ☐ | ☐ | ☐ | 歌单歌曲接口特殊 |
| IOS-E06 | 汽水 `soda` | ☐ | ☐ | ☐ | ☐ | 无签名时可能只有试听 |
| IOS-E07 | Apple Music `apple` | ☐ | ☐ | ☐ | ☐ | 下载通常仅 preview |
| IOS-E08 | Spotify `spotify` | ☐ | ☐ | ☐ | ☐ | 匿名可用；下载通常仅 preview |
| IOS-E09 | Bilibili `bilibili` | ☐ | ☐ | ☐ | ☐ | 支持 FLAC |
| IOS-E10 | Jamendo `jamendo` | ☐ | ☐ | ☐ | ☐ | 歌单搜索可能为空 |
| IOS-E11 | JOOX `joox` | ☐ | ☐ | ☐ | ☐ | |
| IOS-E12 | 千千 `qianqian` | ☐ | ☐ | ☐ | ☐ | 歌单搜索可能为空 |
| IOS-E13 | 5sing `fivesing` | ☐ | ☐ | ☐ | ☐ | |

判定：能搜到、能播、能下（或明确标注仅试听）、有歌词（或明确无歌词）即为通过；失败需附来源、歌曲 ID/链接、截图/录屏。

### F. 安全、隐私与兼容

| ID | 优先级 | 测试点 | 操作与判定 |
| --- | --- | --- | --- |
| IOS-F01 | P0 | 最低系统 | 在 iOS 13.0/13.3（若有设备）启动；若白屏，按 R5 记 P0 并建议提高最低版本或转译 JS |
| IOS-F02 | P0 | 权限最小化 | 首次启动不请求相机/麦克风/通讯录等无关权限；仅出现必要的本地网络权限 |
| IOS-F03 | P1 | Cookie 安全 | Cookie 不出现在页面公开设置接口；退出登录/卸载后不残留可复用凭据 |
| IOS-F04 | P1 | 外部链接 | 外链在 Safari 打开，不在 App 内被劫持；返回 App 后状态正常 |
| IOS-F05 | P1 | 错误提示 | 断网、403、404、源站超时均有可理解提示，不白屏、不无限转圈 |
| IOS-F06 | P2 | 文案/本地化 | 中文文案无乱码；英文系统下关键流程可理解 |
| IOS-F07 | P2 | 图标/启动图 | 桌面图标、启动画面、应用名正确，无黑边/拉伸 |
| IOS-F08 | P1 | 日志隐私 | Console/崩溃日志不打印 Cookie、token、完整下载 URL 中的敏感参数 |

## 6. 发布判定（Exit Criteria）

必须同时满足：

1. **A 全部 P0 通过**：产物、签名、安装、首次启动无阻断。
2. **B/C/D 的 P0 全部通过**：无白屏、无闪退、核心播放和下载可用、后台播放可用。
3. **P1 通过率 ≥ 95%**，未通过项有明确的产品/研发结论和规避方案。
4. 没有新增的 P0/P1 崩溃；没有数据丢失；没有局域网服务暴露。
5. 至少完成：1 台现代 iPad + 1 个旧系统/旧机型（如可得）、1 小时长稳、100+ 首歌单。
6. 发布证据齐全：SHA256、设备信息、版本号、录屏/截图、Console 日志、问题清单。

以下任一情况直接阻断发布：

- 安装后白屏/启动即退；
- 后台播放或锁屏控制不可用且无产品豁免；
- 应用内下载不可用或下载文件丢失；
- 覆盖升级丢设置/Cookie/下载记录；
- `0.0.0.0` 或局域网可访问内置服务；
- iOS 13 声明支持但实际无法启动且未调整最低版本。

## 7. 结果记录模板

复制到执行记录中：

| ID | 优先级 | 结果（Pass/Fail/Blocked/N/A） | 实际表现 | 证据文件 | 备注 |
| --- | --- | --- | --- | --- | --- |
| IOS-A01 | P0 |  |  |  |  |
| IOS-B01 | P0 |  |  |  |  |
| IOS-C04 | P0 |  |  |  |  |
| IOS-D01 | P0 |  |  |  |  |

问题单模板：

```text
标题：[iOS][P0/P1/P2] 简短描述
环境：iPad 型号 / iPadOS 版本 / App 版本+Build / IPA SHA256 / 安装方式
前置：网络、登录状态、来源、歌曲
步骤：
1.
2.
预期：
实际：
复现率：x/y
证据：录屏/截图/Console 日志/崩溃报告路径
补充：是否仅 iOS 出现；Android/Web 是否正常
```

证据目录建议：

```text
ios-<version>-<yyyyMMdd>/
  gate/
  smoke/
  platform/
  matrix/
  soak/
  logs/
  summary.md
```

## 8. 交接说明（给执行 Agent）

执行方必须满足：

- 有 macOS + Xcode，能签名/重签并安装到真机 iPad；
- 能实际操作 iPad（解锁、锁屏、切后台、控制中心、Files）；
- 能取 Console/崩溃日志和录屏；
- 不在测试过程中改业务代码；如需修 bug，另开分支并重新出包回归。

交接包至少包含：

1. 本文档 `ios-release-test-plan.md`；
2. 交接提示词 `ios-test-handoff.md`；
3. 待测 IPA 与 `.sha256`（或 Release 链接）；
4. 测试账号/Cookie（如涉及登录）；
5. 已知问题与豁免说明（尤其 R1–R10）。

执行方返回：

- 填好的结果表（Pass/Fail/Blocked/N/A）；
- 问题单列表（按 P0/P1/P2 排序）；
- 证据目录；
- 一段不超过 10 行的结论：能否发布、阻断项、建议。

如果执行方也只有 Linux/无 iPad：**不要伪造结果**，先完成附录 A 的离线校验，并明确回复“无法执行真机用例”。

## 附录 A. 当前 Ubuntu 主机可做的离线校验

有 IPA 文件时：

```bash
# 1. 校验和
sha256sum -c music-dl-ios.ipa.sha256

# 2. ZIP 完整性
unzip -tq music-dl-ios.ipa
unzip -l music-dl-ios.ipa | grep -E 'Payload/[^/]+\.app/(Info\.plist|MusicDL)$'

# 3. 读 Info.plist（不依赖 macOS plutil）
python3 - <<'PY'
import plistlib, zipfile
ipa = "music-dl-ios.ipa"
with zipfile.ZipFile(ipa) as z:
    name = next(n for n in z.namelist() if n.endswith(".app/Info.plist"))
    plist = plistlib.loads(z.read(name))
for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
            "CFBundlePackageType", "MinimumOSVersion",
            "NSAppTransportSecurity", "NSLocalNetworkUsageDescription"):
    print(key, "=", plist.get(key))
PY
```

macOS 上额外做签名/架构校验：

```bash
unzip -q music-dl-ios.ipa -d /tmp/iosipa
APP=/tmp/iosipa/Payload/MusicDL.app
lipo -archs "$APP/MusicDL"
codesign -dv --verbose=4 "$APP"
codesign --verify --deep --strict "$APP"
security cms -D -i "$APP/embedded.mobileprovision" > /tmp/profile.plist
plutil -p /tmp/profile.plist | grep -E 'UUID|TeamIdentifier|ExpirationDate|application-identifier'
plutil -extract MinimumOSVersion raw "$APP/Info.plist"
plutil -extract NSAppTransportSecurity xml1 -o - "$APP/Info.plist"
```

安装（iOS 17+）：

```bash
xcrun devicectl list devices
xcrun devicectl device install app --device <UDID> /tmp/iosipa/Payload/MusicDL.app
```

## 附录 B. 已知 iOS 相关实现位置（便于定位问题）

| 主题 | 文件 |
| --- | --- |
| iOS 打包/校验/ATS/arm64 | `package_ios.sh` |
| iOS CI 未签名包 | `.github/workflows/ios.yml` |
| 发布流程 iOS 任务 | `.github/workflows/release.yml` |
| 启动、桥接、前后台重载、诊断页 | `desktop_app/main.go` |
| 启动失败页 | `internal/appshell/server.go` |
| 内置服务绑定 127.0.0.1 | `internal/web/server.go` |
| “打开下载目录”平台分支 | `internal/web/open_download_dir.go` |
| 前端播放器/下载/设置 | `internal/web/templates/static/js/app.js` |
| 内置前端依赖 | `internal/web/templates/static/vendor/` |
| iOS 说明与 LiveContainer 排查 | `README.md` “iOS App 构建”章节 |
