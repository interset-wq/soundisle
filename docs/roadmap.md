# 第三版规划（1.0.2 → 1.0.3）

> 状态：**1.0.3 开发中**；上一预发布为 `v1.0.2-android.18`（稳定 release 签名）。
> 更早版本为 `v1.0.1-android.*`（1.0.1，debug 签名）。

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
| 构建    | Android 只出 arm64-v8a 单包（Flutter + 插件 ABI 一并裁剪） | `build.gradle.kts`、`build_mobile_core.sh`、CI           |

验证方式见 `docs/android-verification.md` 与 `docs/testing-guide.md` 第 5.1 节。

## 3. 发布记录

### 1.0.2

1. 4 个签名 secret 已通过 `gh secret set` 写入仓库；
2. 推 tag `v1.0.2` 后 CI 产出预发布 `v1.0.2-android.18`，含 `soundisle-android.apk` 与 `apk-certs.txt`；
3. APK 校验：`1.0.2 (3)`、仅 `arm64-v8a`、签名 SHA-256 `B9:33:E6:…:7E:C2:23`；
4. 从 1.0.1 升级需先卸载一次（签名更换），之后可直接覆盖。

### 1.0.3

1. 版本号 `1.0.3+4`；计划推 tag `v1.0.3` 触发 CI；
2. 已修复 release 资源压缩误删 `drawable/ic_stat_soundisle` 的问题，压缩日志应显示 `reachable from keep xml file`；
3. 下载任务完成后自动写 `<歌曲>.lrc` 与 `<歌曲>.cover.jpg/png/webp`，Android 导出/导入会同步处理侧车；
4. 关于页「播放通知」显示在途通知数量，并支持手动刷新。

## 4. 下一批候选（Android 收口后再启动跨平台）

| 优先级 | 候选                                                     | 说明                                                         |
| ------ | -------------------------------------------------------- | ------------------------------------------------------------ |
| P1     | Android 通知/下载/本地库稳定性回归                       | 继续跟随真机反馈修，暂不扩散到其他平台                       |
| P2     | 桌面端打包补齐（Linux 优先）                             | Android 稳定后再做；需要 `libgtk-3-dev` 等依赖               |
| P3     | 浅色主题                                                 | 目前固定深色；需要统一 `AppColors` 并逐页检查对比度          |
| P3     | iOS 真机验收                                             | Android 收口后再做；计划见 `docs/ios-release-test-plan.md`   |

## 5. 明确不做（本期）

- 不做账号体系、不做云同步；
- 不改音乐源实现，继续跟随上游 `music-lib`；
- 不引入 SQLite / cgo，保持 JSON 持久化与 gomobile 可编译性；
- 不再为 32 位设备与 x86_64 模拟器出包。
