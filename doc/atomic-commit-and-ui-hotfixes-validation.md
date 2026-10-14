# 原子提交与界面热修验证记录

日期：2026-10-14。本轮处理真机暴露的 FAT32 用户分区（vfat）差异、设置弹窗
分辨率、书架行列生效和去彩纹原生组件缺失四项问题。未提交、未发布；结论只覆盖
离机证据，真机仍需复验。

## 根因

Kindle 用户分区是 FAT32：`renameat2(2)` 的 `RENAME_NOREPLACE` / `RENAME_EXCHANGE`
在该文件系统上被拒绝（`EINVAL/ENOSYS/EOPNOTSUPP`）。同一份代码在打包机 ext4 上
一切正常，因此这不是打包/编译阶段能发现的问题，而是运行时能力差异。它同时影响：

| 调用点 | 后果 |
|---|---|
| `settings_store` 迁移备份 | 插件升级后整个消失（已临时预置备份绕过） |
| `download_worker` 下载提交 | 下载到最后阶段报 `path_conflict` |
| `update_files` 插件内更新 | 目录交换无法完成 |
| `stamp`（statx） | 去彩纹高精度元数据不可用（已有优雅降级） |

## 修复

### 1. `preprocess_files.lua`：运行时降级
- 抽出 `_renameAt2`，可注入以便测试；`Files:new{rename_at2=...}`。
- 解析 `ffi.errno()`：`EEXIST` 仍是真冲突；`EINVAL/ENOSYS/EOPNOTSUPP` 或架构无
  该 syscall 时走降级。
- `renameNoReplace`：降级为“目标不存在检查 + `os.rename`”，返回耐久性警告而不
  是失败。下载/设置备份因此可在 FAT 上提交。
- `renameDirectories`：`moveDirectoryNoReplace` 同法降级；`exchangeDirectories`
  改为“经临时名的多步 rename”，失败时回滚，返回非原子降级警告，由更新事务日志
  恢复。
- 顺带修正 `exclusiveWriter` 中不可解析的 `ffi.C.EINTR`（设备上同样取不到该符号）。

### 2. 编译/打包阶段的“测试防守”
- 新增 `spec/koreader_atomic_fallback_integration.lua`：注入 `EINVAL` 的
  renameat2 shim，验证降级仍保持“不覆盖、可提交”。
- 新增 `scripts/verify_atomic_filesystem.sh` + `spec/koreader_atomic_vfat_integration.lua`：
  在**真实 vfat 回环镜像**上跑下载提交、设置迁移备份、目录交换，且分别用原生
  syscall 与强制降级两遍。CI 已接入（`dosfstools` + loop）。
- 未改打包脚本的语法/版本/白名单/SHA256 校验：它抓不了运行时能力问题。

### 3. 设置弹窗分辨率（真机“设置下界超出屏幕”）
- 标题由 9 行压缩为 1 行；版本/KOReader/更新提醒移入“版本与更新状态”条目。
- 将可选按钮两两合并成 8 行（原 12 行），显著降低弹窗高度。
- 新增 `spec/koreader_settings_screen_integration.lua`：在
  `600x800@167 / 1072x1448@300 / 1264x1680@300 / 1448x1072@300` 上断言弹窗
  底边不超出屏幕且留 ≥5% 可达边距。

### 4. 书架行列不生效（“更新后不改变显示数量”）
- 根因与前项同源：设置落盘失败会中断 `applyUiChange`，导致 `on_ui_changed`
  不执行，书架不重排。现在 `SettingsUI.applyUiChange` 用 `pcall` 包住
  `settings:flush()`：失败时仍应用内存值、通知书架重排并提示“未能保存到本机”。
- 新增 `spec/koreader_shelf_layout_update_integration.lua`：真实控制器+网格，
  断言 3×2→2×1→4×2 时当前书架的每页数量随之变化。

### 5. 去彩纹“原生组件缺失”
- `preprocess_service`：在加载前检查 `native/moire-kindlehf.so` 是否存在；缺失时
  给出“本安装包未包含原生去彩纹组件…”的明确原因，而非裸 dlopen errno。
- `preprocess_koreader` 同步加存在性判断，避免直接抛出加载错误。
- 原生组件按项目既有策略只出现在 Colorsoft 实验包；本次已重新构建
  `dist-plugin/koocomic-next-colorsoft-experimental.zip`（含
  `native/moire-kindlehf.so`，SHA-256 `352fc6cd…`），未列入正式发布。

## 证据

- 全量 Lua 5.1 语法检查通过；51+ 组 `spec/*_spec.lua` 全绿。
- KOReader 运行时（v2026.07.1 Linux）集成：下载传输 20 次提交+20 次重启提交、
  文件故障、更新事务/引导、原子降级、书架行列、设置分辨率矩阵全部通过。
- `verify_atomic_filesystem.sh vfat`：原生 `atomic` 与强制 `no-replace commit
  degraded` 两遍均通过；证明修复在真实 FAT 上成立。
- `release_package_spec.py`、`native_preprocess_spec.py` 通过。

## 边界

- 未在真机复验；FAT 降级路径的真机内核行为、断电后的部分交换恢复仍需设备证据。
- 降级提交存在“检查目标不存在→rename”的窄竞争窗口，仅限单写者场景（调用方已
  持有 stage 归属），不是原子保证；已在返回值中标记为降级。
- statx 缺失仍视为功能不可用（优雅降级），未改变。
- 未提升版本、未提交、未推送、未改动线上 `update.json`。
