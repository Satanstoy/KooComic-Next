# Catalog foundation 实施计划

状态：实施中。基线：`71e9f0a`；分支：`codex/catalog-foundation`。

本阶段沿用已确认的 spec 与评审决策，先完成可独立验证的目录基础与旧下载兼容，保持当前书架和单本下载入口。全量枚举、队列响应性和 Colorsoft 交互仍是正式发布门槛，不以模拟测试代替真机证据。文件名冲突尚未确认，本阶段不自动改名或覆盖冲突文件。

## 需求映射

| 需求 | 文件 | 验证 |
|---|---|---|
| 区分账号、卷、文件版本，保留云端书名，不持久化下载签名 | `koobone/catalog_entry.lua` | `spec/catalog_entry_spec.lua`：同名不合并、哈希变化、账号隔离、字段白名单 |
| 系列分组、1/2/10/12.5 排序、版本不增加卷数 | `koobone/series_index.lua` | `spec/series_index_spec.lua`：自然排序、同名不同作者、未分类、输入不变 |
| 基于记录路径识别和打开旧下载，不认领其他卷同名文件 | `koobone/storage.lua`、`ui/book_detail.lua`、`downloader.lua` | `spec/local_path_spec.lua`、`spec/book_detail_spec.lua`：旧路径、缺失记录、目录逃逸、打开路径 |
| 按账号保存安全快照，写入失败保留旧快照 | `koobone/catalog_store.lua` | `spec/catalog_store_spec.lua`：原子替换、账号隔离、错误恢复、敏感字段排除 |
| 只读 limit 探测辅助，不猜 offset/page 或宣布全量 | `koobone/catalog_probe.lua` | `spec/catalog_probe_spec.lua`：28/50/100、重复、异常响应、脱敏证据 |

## TDD 步骤

每个步骤为一个 2–5 分钟操作；每组先观察断言失败，再写最小实现。新增模块测试先通过 `pcall(require, module)` 与明确断言报告功能缺失，不以 Lua 导入错误充当红灯。

1. 安装 Lua 5.1，执行现有语法检查与所有 `spec/*_spec.lua`，保存基线结果。
2. 新建 `spec/catalog_entry_spec.lua`，先断言 `CatalogEntry.normalize(account_id, item)` 保留原始标题且删除签名地址；执行 `lua5.1 spec/catalog_entry_spec.lua` 观察红灯，再实现 `catalog_entry.lua`。
3. 给目录模型增加账号及版本身份边界测试，每次先运行红灯，再补最小归一化逻辑。
4. 新建 `spec/series_index_spec.lua`，断言 `SeriesIndex.group(entries)` 中同卷多个版本只计一卷；红灯后实现分组。
5. 增加小数卷、自然排序、同名作者及缺失系列测试；分别红灯后补齐排序和分组边界。
6. 新建 `spec/local_path_spec.lua`，断言 `Storage:resolveLocalPath(item)` 返回记录的真实旧路径；红灯后实现路径解析。
7. 增加根目录外、符号链接、同名不同卷及不存在文件测试；红灯后完善安全与所有权判断。
8. 新建 `spec/book_detail_spec.lua`，模拟用户点击打开，断言传入历史记录路径；红灯后统一详情页打开路径，并验证下载器已下载入口。
9. 新建 `spec/catalog_store_spec.lua`，断言 `CatalogStore:commit(account_id, entries, meta)` 的写入或 rename 失败不覆盖旧快照；红灯后实现可注入文件后端的原子快照。
10. 增加账号隔离、损坏快照和敏感字段测试；红灯后完善校验。此阶段不自动启用未验证的全量目录替换。
11. 新建 `spec/catalog_probe_spec.lua`，断言 `CatalogProbe:run()` 仅请求 28、50、100 且无响应私密字段；红灯后实现有限只读探测。
12. 执行全部回归及 Lua 5.1 语法检查，派 reviewer 审查，修复重要问题并重新验证。
13. 更新 `PROJECT_STATUS.md`、NOTICE 和计划进度，提交经过验证的逻辑单元并推送自己的 fork，创建可审查 PR，不合并或发行。

## 验证命令

```bash
find koocomic.koplugin spec -type f -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
for spec_file in spec/*_spec.lua; do lua5.1 "$spec_file" || exit 1; done
git diff --check
```

预期：语法检查退出 0，每个 spec 输出 OK，差异检查无非预期空白。原始归档 spec 的 Markdown 硬换行保留，不在此阶段重写。
