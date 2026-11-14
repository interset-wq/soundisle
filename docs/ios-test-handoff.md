# 交接提示词：请执行 MusicDL iOS 正式版真机测试

> 用途：把下面整段内容发给具备 **macOS + Xcode + iPad** 的另一个 Agent。
> 当前 Ubuntu 主机无法连接 iPad、无法签名安装，因此真机测试必须由执行方完成。

---

## 任务

在 macOS + 真机 iPad 上，执行 `go-music-dl` iOS 正式版测试，产出可发布结论和问题清单。

- 仓库：`/home/interset/music-proj/tmp/go-music-dl`（如执行方在另一台机器，请使用对应 clone）
- 测试计划：`/home/interset/music-proj/docs/ios-release-test-plan.md`（先完整读一遍）
- 基线版本：`v1.1.5`，commit `c445ddd`，2026-11-09
- 待测产物：`music-dl-ios.ipa` 或需要重签的 `music-dl-ios-unsigned.ipa`，以及同名 `.sha256`
- 发布页：https://github.com/guohuiyuan/go-music-dl/releases

## 范围

- **只测 iOS。** 按用户要求，Android 正式版测试跳过，不要花时间在 Android 上。
- 必须覆盖测试计划中的 Gate、Smoke、iOS Platform、渠道矩阵、长稳。
- 重点验证测试计划第 2 节的高风险项 R1–R10，尤其是：
  1. 后台/锁屏播放是否持续；
  2. 锁屏和控制中心能否控制播放；
  3. 播放中长时间后台再回前台是否白屏；
  4. “保存到本地目录”和“浏览器下载”在 iOS 上是否可用；
  5. 下载文件是否只能留在 App 内；
  6. 默认相对目录 `data/downloads` 在 iOS 上是否真的可写；
  7. 文件夹导入是否可用；
  8. iOS 13.0–13.3 是否因 JS 语法白屏；
  9. iOS CI 版本号与应用版本是否不一致。

## 硬性要求

1. **真实设备执行**，不要用模拟器结果代替真机；不要用 LiveContainer 的结果代替直接侧载结论。
2. 未签名 IPA 不能直接安装，先按组织要求重签；不要因为“未签名包装不上”就判失败。
3. 不修改业务代码。若需修 bug，另开分支、重新出包并回归，不要边测边改同一个包。
4. 每个失败项必须有：设备型号、iPadOS 版本、App 版本+Build、IPA SHA256、复现步骤、预期/实际、录屏或截图、Console/崩溃日志。
5. 无法执行的用例标 `Blocked`，不要标 `Pass`；没有证据的结论视为无效。
6. 先跑 Gate（A+B），Gate 不通过立即停止并汇报，不要继续堆用例。

## 环境准备

- macOS 15+、Xcode 16+、Command Line Tools。
- iPad（arm64），至少一台现代机型；有 iOS 13/14 旧设备更好。
- 开发者账号 + 匹配 Bundle ID 的 provisioning profile（包含测试设备 UDID），或 SideStore/AltStore 重签。
- iPad 与 Mac 连接；准备 Wi-Fi、蜂窝、飞行模式、弱网/代理。
- 工具：Xcode Devices、Console.app、Safari Web Inspector、Files、屏幕录制。
- 测试数据：网易云/QQ 等至少 3 个来源歌曲、100+ 首歌单、本地音频文件、非音频文件。

## 执行步骤

1. 校验产物：
   ```bash
   shasum -a 256 -c music-dl-ios.ipa.sha256
   unzip -tq music-dl-ios.ipa
   ```
2. 检查 Info.plist、arm64、签名、描述文件（命令见测试计划附录 A）。
3. 安装并首次启动；记录实际 `CFBundleShortVersionString` / `CFBundleVersion`。
4. 按测试计划顺序执行：
   - Gate：A01–A10、B01–B05；
   - Smoke：C01–C16（P0 必跑）；
   - Platform：D01–D20；
   - Matrix：E01–E13（每个来源 1 首，P0 来源全跑）；
   - Soak：D20 连续 1 小时。
5. 每完成一批，先更新结果表，再开始下一批。
6. 结束后按 P0/P1/P2 汇总问题，给出“可发布 / 有条件发布 / 不可发布”的结论。

## 建议的证据目录

```text
ios-v1.1.5-<yyyyMMdd>/
  gate/
  smoke/
  platform/
  matrix/
  soak/
  logs/
  summary.md
```

## 必须返回的内容

1. 填好的结果表（ID、优先级、Pass/Fail/Blocked/N/A、实际表现、证据路径）。
2. 问题单（标题、环境、步骤、预期、实际、复现率、证据）。
3. 发布结论，不超过 10 行：
   - 是否可发布；
   - 阻断项；
   - 建议修复顺序；
   - 未覆盖/Blocked 的范围。
4. 明确说明是否覆盖了 R1–R10；没覆盖的写原因。

## 如果执行方也无法做真机测试

不要编造结果。只做以下事情并说明：

- 完成测试计划附录 A 的离线校验（SHA256、ZIP、Info.plist）；
- 静态确认 R1–R10；
- 回复“缺少 macOS/iPad，无法执行真机用例”，并列出需要补充的资源。

---

**开始前请先回复：设备型号、iPadOS 版本、安装方式、IPA SHA256、计划执行的时间盒。**
