# BESS 纯血鸿蒙版

独立原生 HarmonyOS 工程，使用 ArkTS、声明式 ArkUI、Stage 模型、ArkData RelationalStore、Media Kit、Core File Kit 和 Crypto Architecture Kit。首版固定：

- Bundle ID：`com.bess.salestrainer`
- 版本：`versionCode=2`、`versionName=0.2.0`
- 基线：HarmonyOS 6.0.0（API 20）
- 设备：手机
- 网络：不申请网络权限，完全离线

## 目录

- `entry/src/main/ets/domain`：领域模型、仓储接口、FSRS v6。
- `entry/src/main/ets/data`：ArkData、语料/文章安全导入、媒体、设置、本地提醒、`.bessbackup` v1。
- `entry/src/main/ets/features`：词汇、场景、文章和设置四个入口。
- `entry/src/main/ets/ability`：Stage Ability 与依赖容器。
- `entry/src/ohosTest`：FSRS 金向量和备份容器测试。
- `scripts`：契约检查与正式发布脚本。
- `docs`：签名、邀请测试、升级、隐私及发布说明。

## 构建前置

当前仓库不包含 DevEco Studio、HarmonyOS SDK、华为证书或 AGC Profile。请安装 DevEco Studio 6.0.0 Release 与 API 20 SDK，并在 DevEco 中打开本目录。

Android 的两份内置包是唯一内容源。运行以下 Hvigor 任务会先校验锁定的 SHA-256，再复制到生成资源目录并构建 APP：

```powershell
hvigorw --mode project -p product=default -p buildMode=debug prepareBessAssets
```

修改 Android 内置包后，构建会故意失败。只有在核验新语料后，才可更新 `assets.lock.json` 中的 SHA-256。

## 检查与测试

不依赖 SDK 的静态检查：

```powershell
.\scripts\verify-contracts.ps1
```

安装 API 20 SDK 后，在 DevEco Studio 执行 `entry` 的 OHOS Test/UI Test，并在 HarmonyOS 6.0 API 20 和 6.1 API 24 真机上执行 `docs/TEST_MATRIX.md`。

## 正式发布

按照 [SIGNING_AND_AGC.md](docs/SIGNING_AND_AGC.md) 配置仓库外正式签名后执行：

```powershell
$env:BESS_HARMONY_RELEASE_READY = 'YES'
.\scripts\build-release.ps1
```

脚本输出 APP、已签名 HAP、SHA-256、更新说明、安装升级指南和离线隐私说明。AGC 登录、实名认证、证书/Profile 签发、测试群组和最终发布仍必须由账号持有人操作。

## 数据规则

- 数据库 schema 1 只允许显式事务迁移；遇到高版本数据库拒绝启动，绝不重建或清空。
- `.bessbackup` v1 与 Android/Windows 使用相同字段顺序、显式 null/default、PBKDF2-HMAC-SHA256 600,000 次和 AES-256-GCM。
- 恢复是单事务完整覆盖学习状态；不会覆盖设置、正文、音频和导入文章。
- 语料不一致时保留长期记忆和日志，词汇进行中断点改为 `EXPIRED`，场景进行中会话改为 `ABORTED_CORPUS_CHANGED`。
- 卸载会删除应用沙盒，必须先导出备份。
