# D1.1：队列核心TDD执行计划

本检查点只交付下载DTO/队列与持久化契约，不开放尚无真实worker的批量按钮。

| 小任务 | 文件 | 红灯与绿灯命令 | 完成条件 |
| --- | --- | --- | --- |
| 稳定身份及批量分类 | 新download_queue.lua、download_queue_spec.lua | lua5.1 spec/download_queue_spec.lua | 原名保留、去重/已下载/非法计数、白名单快照 |
| 串行状态和资源 | 同上 | 同上 | pause/resume、阶段合法、旧回调/取消确认/token隔离 |
| 保存失败和重启 | 同上 | 同上 | 开始前保存失败不启动；损坏ID/快照拒绝；运行项恢复为interrupted |
| 原子存储适配 | 新download_queue_store.lua、download_queue_store_spec.lua | lua5.1 spec/download_queue_store_spec.lua | 有界JSON、保存失败不替换旧快照、账号路径隔离 |
| 真实文件集成 | 新koreader_download_queue_integration.lua | 官方runtime ./luajit /绝对路径/spec/koreader_download_queue_integration.lua /绝对路径/checkout | 实际保存/重启、链接拒绝、无会话或签名URL |
| 检查点 | CI、spec证据、PROJECT_STATUS.md | 全部spec、luac5.1、git diff --check、真实runtime | 独立review、提交推送、CI全绿 |

每个测试扩展先运行观察缺失行为的失败，再写最小实现。依赖采用现有CatalogEntry、ResourceCoordinator和PreprocessFiles安全文件API，不另建文件系统。真实签名解析/传输/EPUB校验属于下一检查点D1.2，不把异步stub当成网络验收。
