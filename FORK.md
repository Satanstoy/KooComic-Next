# 派生仓库维护说明

## 来源与许可

- 上游：[jackchensky/KooComic](https://github.com/jackchensky/KooComic)。
- 派生仓库：[Satanstoy/KooComic-Next](https://github.com/Satanstoy/KooComic-Next)。
- 当前设计工作基于上游提交 `df1de69`（Document v0.4.1 release）。
- 继续使用 `AGPL-3.0-only`，保留根目录及插件目录的 LICENSE、NOTICE 和原有版权声明。
- GitHub fork 关系与完整 Git 提交历史用于追溯上游来源及派生修改。

2026-10-12 的初始化修改包含开发文档：规格归档、领域术语、设计评审决策、ADR 和派生仓库说明。随后开始目录基础、路径兼容与只读探测的源码开发，验证范围见 `doc/catalog-foundation-validation.md`。完整 Next 工作流尚未完成；后续源码修改应记录日期、行为变化及验证结果，发行包须附带原有许可证和署名，并提供对应版本的源代码。

## 分支与远程

`origin` 指向本派生仓库，`upstream` 指向上游。`main` 保存经过验证的派生开发基线，后续功能使用 `codex/` 前缀的独立分支；通过小范围提交和 PR 审查合入。当前规格与决策作为初始化文档直接纳入基线。

同步上游时先 fetch 并审查差异，确认兼容后使用普通 merge 保留历史。不强制推送、不重写已发布历史，不将派生修改推送到上游；向上游贡献时另开 PR。

```bash
git fetch upstream
git log --oneline main..upstream/main
git diff main...upstream/main
```

## 设计文档

`doc/KooComic_Next_SPEC.md` 是原始草案；`docs/design-review-decisions.md` 和 `docs/adr/` 保存后续已确认的补充与修正，`CONTEXT.md` 仅保存领域术语。评审记录不是实现完成报告。开始实施前统一更新规格，且不能将原始草案中的实施指令视为自动执行授权。

## 验证与发行

源码修改遵循 `CONTRIBUTING.md` 中的 Lua 5.1 语法检查及回归测试，设备交互与网络行为还需 Kindle/KOReader 真机验证。只在确认发布时提升版本及创建标签；上游历史标签不代表派生项目已经发行。

现有插件更新地址、上游 README 的安装链接和发布徽章仍属于上游。派生版正式发行前必须配置并验证自己的更新清单、下载地址与回滚策略，避免派生版本被上游更新包替换。GitHub fork 的 Actions 需在仓库中显式启用后才会运行；未运行的 CI 不应被称为通过。
