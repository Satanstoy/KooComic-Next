# 独立预处理基础验证记录

日期：2026-10-12。此批交付为纯 Lua 控制核心和 host 单页滤波原型，不是可在 Kindle 上执行的完整 EPUB 处理功能。

## TDD 与审查

- 资源协调器、处理身份、独立队列及安全文件事务分别先以缺失模块断言观察红灯，再实现最小行为与回归。
- native 测试先以未构建原型观察失败，随后导入固定来源的 FFT 并构建 host 库。
- 补充测试复现异常进度值、缺失任务身份、处理参数精度冲突、日志后临时文件变化、缓冲区长度不足及四通道 signed-int 索引跨度溢出，修复后全部通过。
- 只读 reviewer 发现的快照字段校验、事务临时文件再校验及 native 索引跨度问题均已修复；新增文件后端/worker 使用注入契约，不使用占位实现宣称设备可执行。

## 本机验证结果

```bash
find koocomic.koplugin spec -type f -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
for spec_file in spec/*_spec.lua; do lua5.1 "$spec_file" || exit 1; done
make -C native/preprocess
python3 spec/native_preprocess_spec.py
./scripts/package_release.sh v0.4.1 Satanstoy/KooComic-Next dist-ci
unzip -tq dist-ci/release/koocomic.koplugin-v0.4.1.zip
(cd dist-ci/release && sha256sum -c koocomic.koplugin-v0.4.1.zip.sha256)
python3 -m json.tool dist-ci/release/update.json
git diff --check
```

20 组 Lua specs、Lua 5.1 语法、6 项 native 单元测试及包验证均通过。host 构建成功；未改动的 KissFFT 上游代码有一处 signedness 编译警告，未宣称编译零警告。CI 新增 host 构建与测试步骤；GitHub 工作流结果另行确认。

上游 vendor 按字节保留，包括原有行尾空白；完整 `git diff --cached --check` 会报告这些上游空白。自有改动以 `git diff --cached --check -- . ':(exclude)native/preprocess/vendor/**'` 验证通过，导入文件另外用 `cmp`/`diff -rq` 对固定来源逐字节核对，不为消除空白报告修改第三方源码。

测试包仅用于包结构回归，沿用上游版本号和说明，不是 Next 发布；没有创建 GitHub Release。native host `.so` 被忽略且不进入插件包。

## 尚未完成

- 设备进程 worker、LuaJIT/native ABI、图片 codec、EPUB manifest 解析和安全逐页重建。
- 真实文件指纹/空间/锁/原子提交后端、任务文件持久化及启动事务日志恢复。
- 与实际下载器、删除、阅读、重新下载的资源协调接入和管理 UI。
- Colorsoft A/B/C 画质、翻页性能、峰值内存及真实漫画的长任务测试。
- Bookshelf 渲染组件迁移与主书库完整 Next UI 工作流。

这些边界未通过前，正式插件没有预处理执行入口；下载结果和默认文件名不受此批代码影响。
