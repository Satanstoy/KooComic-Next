# 彩色设备去彩纹：启用条件与单一包分发

日期：2026-10-14。变更：去彩纹不再按机型硬编码，也不再要求用户区分实验/正式包。

## 运行时启用条件

- 旧：`Device.model=="KindleColorSoft" and ffi.arch=="arm"`（只认 Colorsoft 机型名）。
- 新：`ffi.arch=="arm" and Device:hasColorScreen()`（`preprocess_service.colorCapable`）。
  即任何彩色墨水屏 ARM 设备（Kindle Colorsoft、Kobo Libra Colour / Clara Colour
  等 Kaleido 彩屏）都自动启用；非彩屏或非 ARM 保持不可用。
- 原生库按平台选择：`native/moire-kobo.so`（Kobo）/ `native/moire-kindlehf.so`
  （其它 arm，含 Colorsoft）。二者 ABI 同为 armv7 hard-float，但 libc sysroot 不同，
  因此各自独立构建。文件缺失时给出明确原因并优雅降级，不影响插件加载。

## 单一包分发

- 新增 `scripts/native_targets.py`：kindlehf/kobo 两个目标的 SDK 源/校验和、
  交叉编译前缀、编译标志、ABI/依赖/`qemu-arm` 静态烟测检查。
- 新增 `scripts/package_native.py`：为每个受支持彩屏目标构建 `.so`，输出
  `native/{moire-*.so, licenses/*, build.json}`。
- 新增 `scripts/package_native_merge.py`：校验 native 目录并并入插件包。
- `scripts/package_release.sh`：设置 `KOOC_NATIVE_DIR` 时把 native 目录并入正式包；
  未设置时行为不变（纯 Lua 包，用于轻量测试）。
- `release.yml`：发布前先构建全部原生目标，再打**一个**正式包（内置
  `moire-kindlehf.so` + `moire-kobo.so`）；用户下载一个包，彩屏设备装上即用。
- `package_colorsoft.py`：改用共享模块，实验包同时包含两个 `.so`；
  实验/正式包的差异只体现在 `build.json` 的 `channel`。

## 证据

- `python3 scripts/package_native.py --sdk-dir <dir> --output <dir>`：kindlehf 与
  kobo 均构建成功，ELF32/ARM/hard-float、`Tag_ABI_VFP_args`、`koocomic_filter` 符号、
  依赖 `libc.so.6/libm.so.6`、`qemu-arm` 静态烟测通过。
- `KOOC_NATIVE_DIR=… ./scripts/package_release.sh …`：单个 ZIP 内含
  `native/moire-kindlehf.so`、`native/moire-kobo.so`、`build.json`、两个许可文件。
- `spec/release_package_spec.py`（纯 Lua 路径）与重构后的
  `spec/colorsoft_package_spec.py`（双目标、可复现、溯源）通过。
- `spec/preprocess_service_spec.lua` 覆盖 `colorCapable` 与按平台的原生路径；
  全量 Lua 5.1 语法与 51 组回归通过；KOReader 运行时文件故障 / EPUB / 便携路径集成通过。

## 边界

- Kobo 目标已交叉编译并按 ARM ABI 校验，但**未在 Kobo 真机做动态加载验证**
  （`dynamic_device_load_verified=false`）；`qemu-arm` 静态烟测不替代真机。
- 版本号未提升（仍是 0.4.1）；未改线上清单；原生组件仅在正式发版工作流中随包。
