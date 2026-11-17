# 声屿 Soundisle

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)

声屿目标是跨平台音乐播放器（Android / iOS / Windows / macOS / Linux），当前以 **Android 为主平台**，
先把 Android 的通知、下载、本地库与稳定性收口，再逐步适配其他系统。界面接近手机自带音乐 App，
核心播放与曲库能力由内嵌的 Go 服务提供，不依赖任何云端部署。

- Flutter 负责全部 UI
- Go 核心（[music-lib](https://github.com/guohuiyuan/music-lib)）监听 `127.0.0.1` 的 HTTP/JSON 接口
- Android / iOS 通过 gomobile 生成的原生库在进程内启动核心
- 桌面端启动随包分发的 `soundisle-core` sidecar

## 功能

- 搜索（歌曲 / 歌手 / 专辑 / 歌单）、粘贴链接直接解析
- 播放页、逐行歌词、播放队列、后台播放与通知栏控制
- 排行榜、歌单与专辑详情、收藏、自建歌单、下载管理
- 下载自动保存歌词与封面；本地播放可离线显示，并随导出/导入同步
- 本地音乐支持关键词搜索、按歌手/专辑分组，旧下载可一键补全缺失资源；重复下载会自动跳过已存在的歌曲
- 多音源切换、Cookie 配置、扫码登录
- 深色主题、移动端底部导航、桌面端 NavigationRail

## 仓库结构

```
app/                 Flutter 应用（包名 app.soundisle.music）
backend/             Go 音乐核心（HTTP/JSON + gomobile 入口）
  internal/api/      REST 路由、鉴权、持久化
  mobile/            gomobile 导出的 Start / Stop / Version
scripts/             构建脚本
docs/                iOS 构建与验收记录
```

## 构建 Android APK

前置条件：Flutter 3.47+、Go 1.26+、Android SDK（含 NDK）、JDK 17+。

```bash
# 1. gomobile（只需一次）
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
gomobile init

# 2. 生成内嵌核心并打包 APK
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
./scripts/build_android.sh release

# 产物：app/build/app/outputs/flutter-apk/app-release.apk
```

`scripts/build_android.sh` 等价于：

```bash
./scripts/build_mobile_core.sh android   # -> app/android/app/libs/musiccore.aar
cd app && flutter build apk --release
```

也可以先执行 `flutter build apk --debug` 得到调试包；未生成 AAR 时工程仍可编译，
但运行时会提示「音乐核心未集成」。

安装到已连接的设备：

```bash
adb install -r app/build/app/outputs/flutter-apk/app-release.apk
```

> 从 1.0.2 起使用统一的 release keystore 签名，后续版本可覆盖升级。
> 本地与 CI 配置方法见 [`docs/signing.md`](docs/signing.md)。

## 构建桌面端

```bash
# 1. 编译 sidecar
./scripts/build_backend.sh

# 2. 运行（自动在可执行文件目录 / backend/bin 查找 core）
cd app
flutter run -d linux    # 或 windows / macos
```

部署时把 `backend/bin/soundisle-core` 放到 Flutter 可执行文件同目录，或设置
`SOUNDISLE_BACKEND` 指向它。Linux 需要 `libgtk-3-dev` 等桌面开发库。

## iOS

```bash
./scripts/build_mobile_core.sh ios   # 需要 macOS + Xcode
cd app && flutter build ios
```

`AppDelegate.swift` 通过 `#if canImport(MusicCore)` 条件接入，未生成 XCFramework 时工程仍可编译。
详见 `docs/ios-release-test-plan.md`。

## HTTP 接口

核心只监听回环地址，除健康检查与音频流外都需要 token：

- 白名单：`/api/health`、`/api/stream/*`、`/api/library/stream`
- 其余接口：`X-Music-Token` 请求头或 `?token=` 参数

数据（设置、收藏、歌单、Cookie、下载）以 JSON 文件保存在应用数据目录，不使用 SQLite。

Android 只构建 `arm64-v8a`（覆盖现代真机，不支持 32 位设备与模拟器）。

Android 验收步骤见 `docs/android-verification.md`，完整测试与排障手册见
`docs/testing-guide.md`。反馈问题时可用 `scripts/collect_android_diagnostics.sh`
一键收集版本、日志、媒体会话与导出文件信息。

版本规划与后续候选见 [`docs/roadmap.md`](docs/roadmap.md)。

## 许可证

本项目以 **GNU AGPL-3.0** 发布，详见 [LICENSE](LICENSE)。内嵌的
[music-lib](https://github.com/guohuiyuan/music-lib) 同样采用 AGPL-3.0，
因此整体分发（包括通过网络提供服务）需遵守 AGPL 的开源义务。
第三方组件与免责声明见 [NOTICE](NOTICE)。

## 已知限制

- Android 使用稳定 release 签名（1.0.2 起），仅构建 arm64-v8a
- 媒体源可用性取决于上游 `music-lib` 与各平台 Cookie 状态
- 下载在服务器支持 `Range` 时可断点续传；不支持时自动从头重新下载
- 歌词/封面取决于音源是否提供；缺失时只保存音频，任务状态会显示实际保存到的资源
- 卸载会清空 App 内歌单/收藏/下载记录；已导出到 `Music/声屿` 的歌曲可在「音乐库 → 本地」一键导入
- 本地音乐支持长按多选：全选、批量加入播放队列/歌单、批量删除（只删 App 内副本）
- 本地音乐可按歌曲/歌手/专辑切换视图，分组可展开、整组播放与整组勾选
- Windows / macOS 包需要在对应系统或 CI 上构建
