# R2-12：v4 设置迁移

1. settings_migration_spec：v1/v2/v3/新安装、未来schema、损坏类型及保存失败先红；保留目录、记录、UI和记住密码选择。
2. settings_store_spec：序列化Lua数据、设置元数据备份、排他临时创建、同步后替换；注入写/备份/替换失败，旧文件不变。
3. settings.lua：深拷贝迁移，v4产品/处理profile默认，清除非Next旧更新候选；所有flush经原子存储，未知版本拒绝写入。
4. 官方KOReader集成：实际旧Lua设置、备份和升级读取，坏文件/未来schema不改写，符号链接拒绝。
5. 运行完整Lua回归、原生测试、审查与CI，提交独立检查点；设备覆盖安装保留待验收。
