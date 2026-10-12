# D1.2a：独立下载传输与EPUB校验

复用AsyncTask隔离HTTP、PreprocessFiles安全文件和已有EPUB结构解析。
此检查点只返回已校验.part，不提交最终路径，不直接作为Queue.worker使用。
D1.2b主进程账号/占用复核与原子提交接通后，才能交给队列判为completed。

1. 新增失败测试：download_transport模块、同步API不在start调用线程运行。
2. 实现子进程解析签名、实际下载、大小预算、同步及SHA；不持久化URL。
3. 新增验证器失败测试并实现：ZIP/manifest/spine及全部资源CRC读取。
4. 实际localhost HTTP测试：生成EPUB下载成功、HTML拒绝、取消进程回收。
5. 回归、review、提交推送；注明无最终提交/无UI绑定，不越过发布门槛。
