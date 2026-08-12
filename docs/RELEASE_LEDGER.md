# HarmonyOS 发布台账

| 版本 | versionCode | Bundle ID | DB | 语料格式 | 备份兼容 | 发布证书 SHA-256 | APP SHA-256 | 已知限制 |
|---|---:|---|---:|---|---|---|---|---|
| 0.2.1 | 3 | com.bess.salestrainer | 1 | besspack 2 / bessarticle 1 | bessbackup v1 | eb958a3b9e9bc57c772518ffddfff6a363204c522c5b3da155b5ac160faf5138 | f4e3e502926f5401f1ea6562b01decc902da2a2381b53eb6e040569de09e029b | API 20 模拟器核心页面与音频冒烟通过；尚未完成 Android 全状态截图 0.98 相似度与真机验收 |
| 0.2.0 | 2 | com.bess.salestrainer | 1 | besspack 2 / bessarticle 1 | bessbackup v1 | eb958a3b9e9bc57c772518ffddfff6a363204c522c5b3da155b5ac160faf5138 | a92a02f2842fa5af51b269f4326be33704ab6eab37e0c55ecda54d467bca4818 | 首发仍需 API 20/24 真机与邀请测试验收 |

## 0.2.1 验签记录（2026-08-04）

正式签名构建与产物位于独立 DevEco 工作工程 `E:\code\bess_harmony_project\harmonyos`；本仓库 `harmonyos/` 不保存证书、Profile、密钥库或口令。

| 检查项 | 结果 |
|---|---|
| 发布 Profile | `type=release`，`bundle-name=com.bess.salestrainer`，`app-distribution-type=app_gallery`，`verify-profile` 通过 |
| HAP 验签 | `BESS-HarmonyOS-v0.2.1-signed.hap`，`verify-app success`，codesign 通过，摘要算法 SHA-256 |
| APP 验签 | `BESS-HarmonyOS-v0.2.1.app`，`verify-app success`，摘要校验通过 |
| 版本与目标 | `versionName=0.2.1`，`versionCode=3`，`compatibleSdkVersion=20`，`targetSdkVersion=20` |
| 权限与后台模式 | 仅 `PUBLISH_AGENT_REMINDER`、`KEEP_BACKGROUND_RUNNING`；`audioPlayback`；无 INTERNET、MICROPHONE、WebView |
| 证书指纹 | `EB:95:8A:3B:9E:9B:C5:7C:77:25:18:FF:DD:FF:F6:A3:63:20:4C:52:2C:5B:3D:A1:55:B5:AC:16:0F:AF:51:38` |
| 产物 SHA-256 | APP `f4e3e502926f5401f1ea6562b01decc902da2a2381b53eb6e040569de09e029b`；HAP `4e45947f0f6870f28f4b2517c2b177948ef321d9e18ad290fc774422861fd6e0` |
| 产物路径 | `E:\code\bess_harmony_project\harmonyos\artifacts\v0.2.1\` |
| 模拟器冒烟 | API 20 `BESS_API20` 干净安装成功；词汇三档评价/下一条、情景音频门槛、文章列表/正文高亮/播放进度/播放暂停及完成后重播、设置入口均已运行验证；回到桌面后音频与进度继续，后台播放通过 |
| 验收边界 | 编译、契约、签名结构和核心模拟器路径已验收；不声称已完成 Android 全状态截图 0.98 相似度、导入/备份全部边界用例、HarmonyOS 真机或 AppGallery 分发验证 |

## 0.2.0 验签记录（2026-08-03）

| 检查项 | 结果 |
|---|---|
| 发布 Profile | `type=release`，`bundle-name=com.bess.salestrainer`，`app-distribution-type=app_gallery`，`verify-profile` 通过 |
| HAP 验签 | `BESS-HarmonyOS-v0.2.0-signed.hap`，`verify-app success`，codesign 通过，摘要算法 SHA-256 |
| APP 验签 | `BESS-HarmonyOS-v0.2.0.app`，`verify-app success` |
| 证书指纹 | `EB:95:8A:3B:9E:9B:C5:7C:77:25:18:FF:DD:FF:F6:A3:63:20:4C:52:2C:5B:3D:A1:55:B5:AC:16:0F:AF:51:38` |
| 产物 SHA-256 | APP `a92a02f2842fa5af51b269f4326be33704ab6eab37e0c55ecda54d467bca4818`；HAP `004f232be0ad118dc83af766592eaeda6868f2bb0d7e25641034dde336a1ec58` |
| 产物路径 | `E:\code\bess_harmony_project\harmonyos\artifacts\v0.2.0\` |

每次发布必须填写证书指纹、APP/HAP 校验值、数据库迁移、备份兼容范围和已知限制。不得复用 `versionCode`，不得用降级包处理故障。
