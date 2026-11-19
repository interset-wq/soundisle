# 第三版规划（1.0.2 → 1.0.8）

> 状态：**1.0.9 验收包准备中**（UI 打磨）；上一发布为 `v1.0.8-android.35`，再往前是 `v1.0.7-android.31`（稳定 release 签名）。
> 更早版本为 `v1.0.6-android.29`、`v1.0.5-android.26`、`v1.0.4-android.24`、`v1.0.3-android.22`、`v1.0.2-android.18`、`v1.0.1-android.*`（1.0.1，debug 签名）。

## 0. 平台节奏

Android 是当前唯一验收平台。通知、下载、媒体库、后台播放等问题先在 Android 上收口，
稳定后再开始 Windows/macOS/Linux 与 iOS 适配，避免多平台同时改动导致问题难以定位。

## 1. 版本目标

1.0.2 不新增音乐源，只解决 1.0.1 真机验收暴露的问题，并把手感补齐：

- 本地音乐必须能播；
- 签名必须稳定，后续版本能直接覆盖安装；
- 播放时必须有通知栏/锁屏控制；
- 首页局部刷新不能整页闪白；
- 点歌直接进播放页（参考手机自带音乐 App）；
- 下载记录重启后不能凭空消失；
- 卸载重装后，之前导出到 `Music/声屿` 的歌曲能一键导回；
- 首页能直接看到最近播放过的歌曲；
- 本地音乐能多选后批量加入队列/歌单或删除；
- 本地音乐能按歌手/专辑分组浏览；
- 下载歌曲时自动同时保存歌词和封面；
- release 包的通知小图标不能被资源压缩误删。

## 2. 已完成

| 编号    | 内容                                                       | 位置                                                     |
| ------- | ---------------------------------------------------------- | -------------------------------------------------------- |
| BUG-101 | 本地音源 `unknown source: local`                           | `backend/internal/api/stream.go`、`stream_local_test.go` |
| BUG-102 | 统一 release 签名，CI 通过 secrets 注入                    | `app/android/app/build.gradle.kts`、`docs/signing.md`    |
| BUG-103 | 专用单色通知图标、暂停保留通知、关于页可查通知状态         | `ic_stat_soundisle.xml`、`main.dart`、`MainActivity.kt`   |
| BUG-104 | 「换一批」只刷新推荐区                                     | `app/lib/ui/pages/home_page.dart`                        |
| 新增-04 | 点歌直接滑入播放页，可在设置关闭                           | `player_route.dart`、`song_tile.dart`、`app_state.dart`  |
| 新增-05 | 下载历史持久化、中断任务可重试、`.part` 暂存避免半截文件   | `backend/internal/api/downloads.go`                      |
| 新增-07 | 下载断点续传（HTTP Range），`.part` 暂存与自动清理         | `backend/internal/api/downloads.go`、`downloads_resume_test.go` |
| 新增-06 | 播放页倍速（0.75~2.0x）与定时停止（15/30/60 分钟）         | `player_controller.dart`、`player_page.dart`             |
| 新增-08 | 从系统 `Music/声屿` 导入已导出歌曲（MediaStore + 权限）     | `MainActivity.kt`、`storage_bridge.dart`、`library_page.dart` |
| 新增-09 | 播放队列支持长按拖动排序                                   | `player_controller.dart`、`player_page.dart`                 |
| 新增-10 | 首页「最近播放」横滑卡片，本地持久化                       | `app_state.dart`、`home_page.dart`、`player_controller.dart` |
| 新增-11 | 本地音乐多选：全选、批量加入队列/歌单、批量删除             | `library_page.dart`、`api_client.dart`、`library.go`         |
| 新增-12 | 本地音乐按歌手/专辑分组，分组可展开与整组播放               | `local_grouping.dart`、`library_page.dart`                   |
| BUG-105 | Release 资源压缩误删通知小图标，媒体通知完全不显示          | `app/android/app/src/main/res/raw/keep.xml`、`AndroidManifest.xml` |
| 新增-13 | 下载自动保存 `.lrc` 与 `.cover.*`；本地播放可读侧车文件；导出/导入一并处理 | `downloads.go`、`library.go`、`MainActivity.kt` |
| 新增-14 | 旧下载缺歌词/封面可单曲补全，也可一键补全全部缺失资源        | `downloads.go`、`library_page.dart`、`api_client.dart`   |
| 新增-15 | 本地音乐支持关键词搜索，多个关键词按“且”匹配                | `local_grouping.dart`、`library_page.dart`               |
| 新增-16 | 每次启动不再重写 `Music/声屿` 中未变化的音频与侧车文件       | `MainActivity.kt`                                        |
| 新增-17 | 重复点下载/整张专辑下载时跳过已在本地或队列中的歌曲          | `downloads.go`、`server.go`、`app_state.dart`            |
| 新增-18 | 空闲时停止下载轮询，避免每 2 秒唤醒 CPU 与请求本地接口       | `app_state.dart`                                         |
| 新增-19 | 快速连续搜索/点歌时，较早的慢响应不再覆盖较新的结果           | `search_page.dart`、`player_controller.dart`             |
| BUG-107 | 切后台/划掉任务时本地核心被停掉，后台播放与媒体通知一起消失    | `app/lib/main.dart`、`player_controller.dart`             |
| 新增-20 | 浅色主题，设置页可切换「跟随系统 / 浅色 / 深色」              | `theme.dart`、`app.dart`、`settings_page.dart` 及各页面    |
| 新增-21 | 媒体通知常驻：暂停保留、不可误划，队列内可「停止播放」移除     | `main.dart`、`player_controller.dart`、`player_page.dart`  |
| 新增-22 | 关于页可发送测试通知、直达媒体通知渠道设置，便于排查通知问题   | `MainActivity.kt`、`permissions.dart`、`settings_page.dart` |
| 构建    | Android 只出 arm64-v8a 单包（Flutter + 插件 ABI 一并裁剪） | `build.gradle.kts`、`build_mobile_core.sh`、CI           |

验证方式见 `docs/android-verification.md` 与 `docs/testing-guide.md` 第 5.1 节。

## 3. 发布记录

### 1.0.2

1. 4 个签名 secret 已通过 `gh secret set` 写入仓库；
2. 推 tag `v1.0.2` 后 CI 产出预发布 `v1.0.2-android.18`，含 `soundisle-android.apk` 与 `apk-certs.txt`；
3. APK 校验：`1.0.2 (3)`、仅 `arm64-v8a`、签名 SHA-256 `B9:33:E6:…:7E:C2:23`；
4. 从 1.0.1 升级需先卸载一次（签名更换），之后可直接覆盖。

### 1.0.3

1. 版本号 `1.0.3+4`；推 tag `v1.0.3` 后 CI 产出预发布 `v1.0.3-android.22`；
2. 已修复 release 资源压缩误删 `drawable/ic_stat_soundisle` 的问题，压缩日志显示 `reachable from keep xml file`；
3. 下载任务完成后自动写 `<歌曲>.lrc` 与 `<歌曲>.cover.jpg/png/webp`，Android 导出/导入会同步处理侧车；
4. 关于页「播放通知」显示在途通知数量，并支持手动刷新。

### 1.0.4

1. 版本号 `1.0.4+5`，推 tag `v1.0.4` 后 CI 产出预发布 `v1.0.4-android.24`（含 `soundisle-android.apk` 与 `apk-certs.txt`），可覆盖安装 1.0.3；
2. 本地音乐支持按歌名/歌手/专辑/文件名搜索，多个关键词同时生效；
3. 下载页新增「补全全部歌词/封面」，旧下载无需逐首点魔法棒；
4. 补全中的任务显示进度转圈，重启后不会残留“补全中”状态；
5. 已发布的音频/歌词/封面在大小一致时不再重复删除重写，避免每次启动触发媒体库重扫。

### 1.0.5

1. 版本号 `1.0.5+6`，推 tag `v1.0.5` 后 CI 产出预发布 `v1.0.5-android.26`（含 `soundisle-android.apk` 与 `apk-certs.txt`），可覆盖安装 1.0.4；
2. 重复点「下载」或下载已含本地歌曲的专辑时，后端会跳过已存在/进行中的歌曲，不再产生重复任务；
3. 下载提示会说明「已加入 N 首，M 首已存在」，重复点击不再像无响应。

### 1.0.6

1. 版本号 `1.0.6+7`，推 tag `v1.0.6` 后 CI 产出预发布 `v1.0.6-android.29`（含 `soundisle-android.apk` 与 `apk-certs.txt`），可覆盖安装 1.0.5；
2. 下载/补全任务全部结束后自动停止 2 秒轮询，空闲时不再持续请求本地接口与唤醒 CPU；
3. 轮询增加重入保护，单次请求变慢时不会叠加并发请求。

### 1.0.7

1. 版本号 `1.0.7+8`，推 tag `v1.0.7` 后 CI 产出预发布 `v1.0.7-android.31`（含 `soundisle-android.apk` 与 `apk-certs.txt`），可覆盖安装 1.0.6；
2. 搜索请求带代次校验：快速连续搜索时，旧响应不会覆盖新关键词的结果，也不会卡住新搜索；
3. 播放请求带当前歌曲校验：快速连点两首歌时，后点的歌曲生效，旧响应不会抢占播放器；
4. 播放加载状态只在仍对应当前歌曲时结束，避免旧请求把新歌的加载指示提前关掉。

### 1.0.8

1. 版本号 `1.0.8+9`，推 tag `v1.0.8` 后 CI 产出预发布 `v1.0.8-android.35`（含 `soundisle-android.apk` 与 `apk-certs.txt`），可覆盖安装 1.0.7；
2. 浅色主题：新增 `AppThemeColors` 扩展，页面内硬编码的白色/黑色改为主题感知颜色，封面渐变、二维码白底等有意为之的对比保持不变；
3. 设置页「外观」提供「跟随系统 / 浅色 / 深色」，写入后端 `themeMode`，重启后保持；
4. 通知常驻：媒体通知设为 ongoing，暂停后仍保留，不再被误划掉；播放队列新增「停止播放」，用于结束会话并移除通知；
5. 修复切后台/划掉任务后本地核心被停止的问题：只要还有已加载的歌曲，本地 HTTP 服务继续运行，后台播放与通知不再被自己切断；
6. 通知排查：关于页新增「发送测试通知」，可绕开媒体会话验证通知权限与渠道；点按「播放通知」直接进入媒体通知渠道设置；
7. 播放开始时再次申请通知权限，避免冷启动时错过系统弹窗。

### 1.0.9（UI 打磨 / 验收包）

1. 版本号 `1.0.9+10`，作为真机验收包；签名与 1.0.2 起一致，可直接覆盖安装 1.0.8；
2. 状态栏/导航栏图标亮度跟随主题，浅色下不再出现白底白图标；无 AppBar 的首页、搜索、播放页也生效；
3. 统一 chip、分段按钮、填充按钮、文字按钮、进度条与分割线样式；列表项圆角与点击水波纹对齐；
4. 播放页：歌词固定行高、精确居中滚动、上下渐隐，拖动时暂停自动滚动；播放按钮加水波纹与主题化光晕；
   队列面板显示总时长，当前行 accent 高亮，新增红色「停止播放」；倍速/定时面板勾选色与剩余时间；
5. 迷你播放器：顶部细边框、浅色阴影、主题色进度条与按钮 tooltip；出现/消失带尺寸动画；
6. 音乐库批量操作栏改用主题 surface，修复浅色下黑图标不可见；搜索入口、发送按钮、歌单头部返回按钮补齐水波纹与语义；
7. 加载骨架改为呼吸式淡入淡出；首页 hero 高度随系统字号增长，播放页底部操作等宽防溢出；
8. Android 原生启动背景使用主题色（浅色 `#FFF7F6FB` / 深色 `#FF0A0A11`），消除冷启动闪白/闪黑；
9. 修复 Android 13+ 媒体通知不出现：资源压缩移除了 `audio_service` 按名称查找的播放/暂停/停止图标，`CustomAction.Builder` 抛 `IllegalArgumentException` 导致 `setState` 中断、前台服务未启动；`res/raw/keep.xml` 显式保留 `@drawable/audio_service_*`。
10. 修复「停止播放」后通知栏残留旧媒体卡片：`audio_service` 的服务被 Activity 绑定，`stopSelf()` 无法销毁，前台通知取消后又被系统补回；新增同包桥接 `SoundisleAudioBridge` 显式 `stopForeground(REMOVE)`（不能 `stopService`，否则 `onDestroy` 会销毁共享 FlutterEngine 导致界面白屏），通知内停止时 Dart 侧检测到播放器回到 idle 后同步清空状态并退回首页。

## 4. 下一批候选（Android 收口后再启动跨平台）

| 优先级 | 候选                                                     | 说明                                                         |
| ------ | -------------------------------------------------------- | ------------------------------------------------------------ |
| P1     | Android 通知/下载/本地库稳定性回归                       | 继续跟随真机反馈修，暂不扩散到其他平台                       |
| P2     | 桌面端打包补齐（Linux 优先）                             | Android 稳定后再做；需要 `libgtk-3-dev` 等依赖               |
| P3     | iOS 真机验收                                             | Android 收口后再做；计划见 `docs/ios-release-test-plan.md`   |

## 5. 明确不做（本期）

- 不做账号体系、不做云同步；
- 不改音乐源实现，继续跟随上游 `music-lib`；
- 不引入 SQLite / cgo，保持 JSON 持久化与 gomobile 可编译性；
- 不再为 32 位设备与 x86_64 模拟器出包。
