# 从 0.2.0 升级到 0.2.1

- Bundle ID 仍为 `com.bess.salestrainer`，版本升级为 `0.2.1 / versionCode 3`。
- 使用同一正式发布证书覆盖安装可保留数据库、学习断点和本地导入内容。
- 数据库仍为 schema 1，`.bessbackup v1` 九类记录格式、字段顺序和加密算法均未改变。
- 升级前建议在“设置 > 学习记录备份”导出并检查一份 `.bessbackup`。
- 本版本在 HarmonyOS 6 API 20 模拟器验收；不声明真机或 AppGallery 分发验证。
