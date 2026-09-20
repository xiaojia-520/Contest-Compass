# 原生客户端构建

赛智荐保留 Flutter Web，并提供 Android、iOS、Windows 和 macOS 工程。Linux 不在支持范围内。

## 通用配置

原生客户端必须在构建时注入公网 HTTPS API 地址：

```text
--dart-define=API_BASE_URL=https://api.example.com/api
```

未传入地址时应用仍可启动，但只显示“服务器地址尚未配置”页面。正式地址和签名密钥不得写入仓库。

## Windows 与 Android

在仓库根目录执行：

```powershell
.\scripts\build-apps.ps1 -ApiBaseUrl 'https://api.example.com/api'
```

脚本会构建 Web、分架构 APK、AAB 和 Windows x64 Release。安装 Inno Setup 并确保 `ISCC.exe` 在 PATH 后，还会生成 Windows `.exe` 安装程序。

Android 正式签名：

1. 复制 `frontend/android/key.properties.example` 为 `key.properties`；
2. 填写本地 keystore 路径和密码；
3. 不要提交 `key.properties` 或 `.jks` 文件。

未提供签名配置时产生的是未签名 Release 产物，仅用于 CI 验证。

GitHub Actions 可选签名 Secrets：

- `ANDROID_KEYSTORE_BASE64`：上传 keystore 的 Base64 内容；
- `ANDROID_STORE_PASSWORD`：keystore 密码；
- `ANDROID_KEY_PASSWORD`：密钥密码；
- `ANDROID_KEY_ALIAS`：密钥别名。

## iOS 与 macOS

Apple 平台必须在安装 Xcode 和 CocoaPods 的 macOS 上构建：

```bash
API_BASE_URL='https://api.example.com/api' bash scripts/build-apple.sh
```

脚本会生成未签名 iOS Release、macOS 通用架构应用和 DMG。正式分发前需在 Xcode 中填写 Apple Team，并配置 Developer ID/Application Distribution 证书。iOS 面向普通用户时通过 TestFlight 分发。

## GitHub Actions

推送 `v*` 标签会触发四个平台构建。仓库 Secrets：

- `API_BASE_URL`：完整 HTTPS API 地址，包含 `/api`；
- Android 签名 Secrets 如上；未配置时流程输出未签名产物；
- Apple 证书留待 Apple Developer 账号就绪后接入，当前流程输出未签名产物。

## 客户端版本发布

管理员登录后在“任务管理 → 客户端版本”创建记录。下载地址必须是外部 HTTPS 地址。客户端启动时检查一次，设置页也可以手动检查；最低支持版本高于当前版本时会触发强制更新。

## 桌面行为

- 默认窗口为 1280×800，最小 900×600；
- 记录上次窗口大小和位置；
- 重复启动会聚焦已有 Windows 窗口；
- 关闭按钮直接退出，最小化保留在任务栏；
- 托盘菜单提供“打开主窗口”和“退出程序”；
- 开机自启默认关闭，可在设置页开启。

## 截止提醒

登录或生成报告后，客户端同步最近比赛，并安排截止前 7、3、1 天当地时间上午 9:00 的系统通知。提醒开关与项目偏好保存在后端。iOS 最多保留 64 个待处理通知，因此客户端只安排最近 60 条。
