# HarmonyOS 验收矩阵

## 自动化

- ArkTS 单元测试：FSRS 共享金向量、未加密/加密备份往返、Unicode 密码、错误密码、密文篡改、未知格式。
- 文件安全：路径穿越、重复条目、截断 ZIP、超限条目、解压总量、JSON 深度和校验不一致。
- ArkData：首次建库、单事务恢复回滚、拒绝高版本数据库、未来 schema 1→2 迁移框架。
- 状态机：五类词汇题型、初学三档、复习四档、重复点击幂等、收藏、强制结束续学；场景逐步揭示、自评与断点。

## 三端互操作

使用固定时间与 Unicode 密码 `储能-pass-2026` 生成样本，分别执行：

- Android → HarmonyOS、HarmonyOS → Android
- Windows → HarmonyOS、HarmonyOS → Windows
- Android → Windows、Windows → Android（既有测试持续保留）

每个方向覆盖加密、未加密、空数据、大量日志、中文、特殊字符、精确断点和语料差异。恢复前记录九类数量，恢复后逐表比对。拒绝样本后再次逐表比对，确认数据库未改变。

## 真机

- HarmonyOS 6.0 / API 20 手机：首次安装、飞行模式全流程、深浅色、字体放大、横竖屏、系统返回、屏幕朗读、音频中断与蓝牙切换。
- HarmonyOS 6.1 / API 24 手机：同上，并验证高版本兼容。
- AppGallery 邀请测试：0.2.0 首装、0.2.0→0.2.1 覆盖升级、签名一致性、学习记录与断点保持。
- 卸载提示：先导出并复检备份，卸载重装后恢复；确认设置、正文、音频和导入文章不从学习备份恢复。

## 发布门禁

- `bundleName=com.bess.salestrainer`，版本号符合台账且 `versionCode` 递增。
- Release 非调试、APP/HAP 已用永久发布证书签名，指纹与台账一致。
- 只声明手机、不申请 INTERNET、不包含 WebView/联网运行时。
- Android 两份内置包与 `assets.lock.json` SHA-256 一致。
- `SHA256SUMS.txt` 可验证最终 APP/HAP。
