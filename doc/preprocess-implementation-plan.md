# 独立预处理首批 TDD 计划

用户已授权按整合后的工程规格实施，先建立不影响下载的独立基础；设备端 worker/EPUB codec 未验证时不开放执行。基线为当前目录基础分支，原有回归测试继续保留。

每项拆为 2–5 分钟的红灯、最小实现、绿灯和重构步骤，顺序执行：

1. `spec/resource_coordinator_spec.lua` 先断言资源互斥与 token 隔离缺失，红灯后实现 `koobone/resource_coordinator.lua`，覆盖重复/旧 token 释放。
2. `spec/preprocess_identity_spec.lua` 先断言任务身份缺失，红灯后实现 `koobone/preprocess_identity.lua`，覆盖参数排序、源变化、算法版本和无标题身份。
3. `spec/preprocess_queue_spec.lua` 先断言独立排队缺失，红灯后实现 `koobone/preprocess_queue.lua`；逐个增加资源等待、worker 回调、取消、重试、进度、快照恢复和持久化失败用例。
4. `spec/preprocess_transaction_spec.lua` 先断言安全提交缺失，红灯后实现 `koobone/preprocess_transaction.lua`；测试备份失败、验证失败、源变化、文件占用和原子提交/恢复。文件后端显式注入，尚无设备 EPUB writer 时不提供伪成功后端。
5. `native/preprocess/` 固定导入 Derainbowify KissFFT 代码与许可；`spec/native_preprocess_spec.py` 先报告原型未构建，编译后验证常量、合成对角频率、色度和内存/尺寸拒绝。仅 host 原型，不声明 Kindle 适配完成。
6. Bookshelf 渲染组件迁移留在下一批 UI 工作中；上游 `grid_margins` 的 10 项几何测试可迁移，另 2 项依赖上游主 widget 源码的接线测试必须改写，不能宣称直接迁移全部 12 项。
7. reviewer 检查独立状态、晚到回调、文件不覆盖与 native 边界；修复后跑所有 Lua specs、Lua 5.1 语法及 native tests。
8. 更新状态与验证记录，提交并推送经过验证的检查点；后续设备管线与 UI 阶段按工程规格继续，不把本批测试绿灯当作 Colorsoft 功能完成。

验证命令：

```bash
find koocomic.koplugin spec -type f -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
for spec_file in spec/*_spec.lua; do lua5.1 "$spec_file" || exit 1; done
python3 spec/native_preprocess_spec.py
git diff --check
```
