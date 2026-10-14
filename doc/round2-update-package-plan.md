# R2-19：安全更新包解压检查点

1. 新建独立`koobone/update_package.lua`，测试先证明普通文件/目录可以解包，
   链接/设备、路径穿越、重复或别名路径、运行数据、总解压量及单文件预算拒绝。
2. 使用Archiver结构化entry.mode/size；只提取有界普通文件到内存，再用Files
   安全排他文件接口落盘。不调用能创建链接的extractToPath。
3. Updater `_extractPackage`委托该模块，保留既有安装前SHA/大小和产品验证。
4. 官方runtime生成ZIP验证实际libarchive读取、普通资源内容、符号链接/CRC损坏
   拒绝；完整回归、review、记录证据并提交。事务升级/回滚不混在此单位中。
