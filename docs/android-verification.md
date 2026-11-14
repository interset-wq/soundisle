# Android 验收清单

产物：`app/build/app/outputs/flutter-apk/app-release.apk`（debug 签名，仅验收用）。

## 安装

```bash
adb devices
adb install -r app/build/app/outputs/flutter-apk/app-release.apk
```

首次打开会请求通知权限（后台播放需要）。若系统拦截「安装未知来源」，在
「设置 → 应用 → 声屿 → 允许安装」中放行。

## 验收项

| # | 操作 | 预期 |
|---|------|------|
| 1 | 冷启动 | 显示启动页后进入首页，无「音乐核心未集成」提示 |
| 2 | 首页 | 推荐歌单 / 排行榜加载出封面 |
| 3 | 搜索「周杰伦」 | 出现歌曲 / 歌手 / 专辑 / 歌单分组，可切换 |
| 4 | 点击歌曲 | 进入播放页并开始播放，进度条与时长正常 |
| 5 | 播放页 | 歌词随播放滚动，可暂停 / 上一首 / 下一首 / 切循环模式 |
| 6 | 通知栏 | 出现媒体通知，可暂停与切歌；锁屏可控 |
| 7 | 收藏 | 点亮红心后「音乐库 → 我喜欢」可见 |
| 8 | 新建歌单 | 输入名称后可在歌单页添加 / 移除歌曲 |
| 9 | 排行榜 | 选择来源榜单，可进入详情并播放 |
| 10 | 下载 | 播放页或列表下载后，「音乐库 → 下载」可离线播放 |
| 11 | 设置 | 切换默认音源、填写 Cookie / 扫码登录后搜索来源变化 |
| 12 | 杀进程重开 | 收藏、歌单、设置仍在（JSON 持久化） |

## 已知限制

- release 包使用 debug 签名，不能上架应用商店
- 音源可用性取决于上游 `music-lib` 与平台 Cookie，个别歌曲可能无版权或 404
- 首次播放需联网；已下载歌曲可离线
- 未集成 AAR 时应用仍可安装，但启动会提示核心缺失

## 排障

```bash
adb logcat -s flutter:V GoLog:V
```

- 提示「音乐核心未集成」：重新执行 `./scripts/build_mobile_core.sh android`
  后重新打包
- 白屏 / 启动超时：确认 `MainActivity` 继承 `AudioServiceActivity`
- 播放无声音：检查通知权限与 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
