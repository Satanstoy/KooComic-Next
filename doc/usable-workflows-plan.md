# 可用工作流实施

本批按已经批准的工程规格推进实际入口，完成判定必须区分代码测试、Linux KOReader 运行及 Kindle 真机证据。

1. `spec/shelf_navigation_spec.lua` 先测试系列/单卷/已下载投影、稳定身份、系列进入返回与分类记忆；实现 `koobone/ui/shelf_navigation.lua`，再接 `bookshelf.lua`。
2. `spec/shelf_layout_spec.lua` 先测试横竖屏、大字号和触控区域；实现布局模块并复用固定版本的 Bookshelf GridMargins/Space。
3. 改 `bookshelf_grid.lua`：分类条、文件夹标签、数量徽标和单行页脚；更新旧结构回归断言，确认失败后修改正式渲染代码。
4. 从官方 Linux KOReader 运行时检查图片、ZIP 和独立进程接口；依赖核查后写真实 EPUB 处理失败测试，再实现逐页 worker、任务持久化和详情/管理入口。
5. 只读 reviewer 检查文件安全与 UI 行为；全量测试、打包、KOReader 运行截图及 CI 后提交推送。Kindle ABI、阅读锁和 Colorsoft 效果不能用 host 结果替代。
