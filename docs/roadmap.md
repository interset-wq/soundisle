# 第三版规划（1.0.2）

> 状态：**开发完成，等待签名 secrets 后发布**。
> 上一版为 `v1.0.1-android.*`（1.0.1，debug 签名）。

## 1. 版本目标

1.0.2 不新增音乐源，只解决 1.0.1 真机验收暴露的问题，并把手感补齐：

- 本地音乐必须能播；
- 签名必须稳定，后续版本能直接覆盖安装；
- 播放时必须有通知栏/锁屏控制；
- 首页局部刷新不能整页闪白；
- 点歌直接进播放页（参考手机自带音乐 App）；
- 下载记录重启后不能凭空消失；
- 卸载重装后，之前导出到 `Music/声屿` 的歌曲能一键导回。

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
| 构建    | Android 只出 arm64-v8a 单包（Flutter + 插件 ABI 一并裁剪） | `build.gradle.kts`、`build_mobile_core.sh`、CI           |

验证方式见 `docs/android-verification.md` 与 `docs/testing-guide.md` 第 5.1 节。

## 3. 待你确认后发布

1. 在 GitHub 仓库添加 4 个签名 secret（值在 `~/.soundisle-signing/github-secrets.txt`）；
2. 推 tag `v1.0.2`，CI 产出 `v1.0.2-android.<run>` + `apk-certs.txt`；
3. 从 1.0.1 升级需先卸载一次（签名更换）。

## 4. 下一批候选（按收益排序）

| 优先级 | 候选                                                     | 说明                                                         |
| ------ | -------------------------------------------------------- | ------------------------------------------------------------ |
| P2     | 本地音乐批量管理                                         | 多选删除、按目录/歌手分组、手动「重新扫描」入口更显眼        |
| P2     | 桌面端打包补齐（Linux 优先）                             | 需要 `libgtk-3-dev` 等依赖；CI 增加桌面构建 job              |
| P3     | 浅色主题                                                 | 目前固定深色；需要统一 `AppColors` 并逐页检查对比度          |
| P3     | iOS 真机验收                                             | 计划见 `docs/ios-release-test-plan.md`，需要 macOS 环境      |

## 5. 明确不做（本期）

- 不做账号体系、不做云同步；
- 不改音乐源实现，继续跟随上游 `music-lib`；
- 不引入 SQLite / cgo，保持 JSON 持久化与 gomobile 可编译性；
- 不再为 32 位设备与 x86_64 模拟器出包。
