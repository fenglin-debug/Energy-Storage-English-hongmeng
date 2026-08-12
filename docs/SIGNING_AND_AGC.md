# Release 签名与 AGC 邀请测试

正式身份永久固定为 `com.bess.salestrainer`。发布证书、Profile、私钥、密码和任何本地签名配置不得提交仓库，也不得通过聊天或邮件发送。

1. 安装 DevEco Studio 6.0.0 Release 和 HarmonyOS 6.0.0（API 20）SDK，以实名认证的中国大陆华为开发者账号登录。
2. 在 AppGallery Connect 创建 HarmonyOS 应用，Bundle ID 必须是 `com.bess.salestrainer`。
3. 创建发布证书与发布 Profile，妥善离线备份私钥、证书和 Profile。至少保留两份离线副本，并记录证书 SHA-256 指纹。
4. 在 DevEco Studio 的 **File > Project Structure > Signing Configs** 中添加正式签名。证书和 Profile 使用仓库外绝对路径；不要勾选或分发 Debug 签名产物。
5. 将 `default` 产品的 Release 构建绑定到正式签名配置。先在 DevEco 中执行一次 Release APP 构建，确认输出包含 signed HAP。
6. 在 PowerShell 当前会话执行：

   ```powershell
   $env:BESS_HARMONY_RELEASE_READY = 'YES'
   .\scripts\build-release.ps1
   ```

7. 在 AGC 创建邀请测试群组，上传 `BESS-HarmonyOS-v0.2.0.app`，填写离线隐私说明和更新说明，发布邀请入口。证书签发、实名认证、后台上传与发布必须由账号持有人完成。

后续版本必须递增 `versionCode`。出现问题时发布更高版本热修复，不允许用户卸载旧版或安装降级包。
