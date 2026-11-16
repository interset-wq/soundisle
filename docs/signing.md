# Android 稳定签名

从 **1.0.2** 起，声屿所有 Android 安装包使用同一个 release keystore 签名。
只要签名不变，后续版本都能直接覆盖安装（`adb install -r` 或点 APK 升级），
不会清空歌单、收藏、Cookie 和下载记录。

> 1.0.1 及更早的包使用 CI 临时生成的 debug 签名，每个构建都可能不同。
> 从旧版升级到 1.0.2 需要**卸载一次**；从 1.0.2 起不再需要。

## 1. 密钥信息

| 项目 | 值 |
| ---- | -- |
| 别名 | `soundisle` |
| 算法 | RSA 4096 / PKCS12 |
| 有效期 | 10000 天（约 27 年） |
| SHA-256 指纹 | `B9:33:E6:A5:C1:4A:50:29:AF:C1:C6:6D:D8:B2:75:27:D4:D2:58:2F:8F:0B:63:69:F4:BC:11:93:97:7E:C2:23` |
| 本地位置 | `~/.soundisle-signing/soundisle-release.jks`（仓库外，勿提交） |
| 本地凭据 | `~/.soundisle-signing/credentials.txt`（权限 600） |

**务必备份** `soundisle-release.jks` 和密码到密码管理器或离线介质。
keystore 丢失后无法再发布可覆盖升级的版本，只能让所有用户卸载重装。

## 2. GitHub Actions 配置

在仓库 **Settings → Secrets and variables → Actions → New repository secret**
添加四个 secret：

| Secret | 内容 |
| ------ | ---- |
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 Base64（单行，无换行） |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | `soundisle` |
| `ANDROID_KEY_PASSWORD` | key 密码（当前与 keystore 密码相同） |

生成 Base64：

```bash
base64 -w0 ~/.soundisle-signing/soundisle-release.jks > keystore.base64.txt
```

`base64 -w0` 在 macOS 上不可用，可改用：

```bash
base64 -i ~/.soundisle-signing/soundisle-release.jks | tr -d '\n' > keystore.base64.txt
```

CI 在构建前会把 secret 还原成 `$RUNNER_TEMP/soundisle-release.jks`，并写入
`app/android/key.properties`。tag / 手动发布的构建如果缺少这些 secret 会直接
失败，避免又生成一个签名不同的包；`main` 分支的普通构建允许回退到 debug 签名
（只作为构建产物，不发布）。

发布时会把 `apk-certs.txt`（`apksigner verify --print-certs` 输出）一并上传，
可用于核对 APK 的 SHA-256 指纹是否与上表一致。

## 3. 本地构建

复制模板并填写：

```bash
cp app/android/key.properties.example app/android/key.properties
```

```properties
storePassword=***
keyPassword=***
keyAlias=soundisle
storeFile=/home/<you>/.soundisle-signing/soundisle-release.jks
```

`app/android/key.properties` 与所有 `*.jks` / `*.keystore` 均已在
`.gitignore` 中忽略。

```bash
cd app
flutter build apk --release --target-platform android-arm64
```

校验签名：

```bash
$ANDROID_HOME/build-tools/<版本>/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

输出的 `Signer #1 certificate SHA-256 digest` 应与第 1 节一致。

## 4. 架构策略

Android 只构建 **arm64-v8a** 一种架构：

- 覆盖目前几乎所有在用的 Android 手机；
- Go 核心（gomobile AAR）同样只包含 arm64；
- 不支持 x86_64 模拟器与 32 位老设备；
- APK 体积更小，CI 构建更快。

对应配置：

- `.github/workflows/android.yml`：`--target-platform android-arm64`
- `scripts/build_mobile_core.sh`：`gomobile bind -target=android/arm64`
- `app/android/app/build.gradle.kts`：`ndk { abiFilters.add("arm64-v8a") }`

`--target-platform` 只约束 Flutter 自身的 `libflutter.so` / `libapp.so`，插件 AAR
（media_kit、jni 等）仍会打包全部 ABI；Gradle 的 `abiFilters` 负责把其余架构
真正剥离。当前 APK 仅含 `arm64-v8a`，体积约 38 MB。

## 5. 更换签名的后果

- 已安装用户无法覆盖升级，必须卸载后重装（App 内数据丢失）。
- 应用商店（若上架）会拒绝新包。
- 因此除非密钥泄露，否则不要重新生成 keystore。
- 若怀疑泄露：立即生成新 keystore、更新 secrets、提升版本号，并在发布说明中
  写明需要卸载重装。
