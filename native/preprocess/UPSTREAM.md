# 原生单页滤波原型

固定来源：[Euphoriyy/derainbowify.koplugin](https://github.com/Euphoriyy/derainbowify.koplugin/tree/f2892a219da65bd765d34ae2140a5dd706dfc42b)，commit `f2892a219da65bd765d34ae2140a5dd706dfc42b`。

`vendor/moire_filter_kissfft.c` 与 `vendor/kissfft/` 从上游同名路径原样复制；上游 GPL-3.0 保存在 `vendor/DERAINBOWIFY_LICENSE`，KissFFT 自带 `COPYING` 保留。新增 `filter.c` 包装输入与预算检查、错误返回和清理，不改变上游的频率掩模。上游原始入口仍存在，调用方只允许调用经过检查的 `koocomic_filter`。

此原型处理已经解码并准备好尺寸的灰阶/RGBX 单页，不负责 EPUB、JPEG/PNG 编解码或任务进程管理。只接受正偶数尺寸和连续 stride；奇数页面需由未来页适配器验证后补边并裁回，不能直接送入滤波器。

检查入口为 `int koocomic_filter(unsigned char *data, int width, int height, int stride, int is_colored, float strength, size_t memory_budget, size_t data_size)`；调用方必须提供真实可访问缓冲区的字节数，不得仅按页面声明尺寸估算。

```bash
make -C native/preprocess
python3 spec/native_preprocess_spec.py
```

实验包通过 `python3 scripts/package_colorsoft.py --output dist-colorsoft` 构建；可用 `--sdk-archive /path/to/kindlehf.tar.zst` 复用本地下载。固定官方 koxtoolchain `2026.08` 的 `kindlehf.tar.zst`，SHA-256 `8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0`，实际前缀 `arm-kindlehf-linux-gnueabihf`。脚本先校验 SDK，再编译 ARMv7/NEON hard-float 库，检查 ELF/依赖/导出符号，运行 QEMU 静态算法烟测，并打包当前完整插件、原生库、两份许可证和来源清单；不会更新 stable 清单或发布 Release。

QEMU 静态烟测不是 `.so` 动态加载验收。该 SDK 的 glibc 2.20 动态加载器在本机 QEMU 中于首次系统调用前触发 `do-rel.h` 断言，使用非 PIE 探针仍复现；因此不以其结果验证设备动态加载。实验清单保留 `device_verified=false` 和 `dynamic_device_load_verified=false`，设备 ABI、实际画质与内存性能仍必须实机验收。

`memory_budget` 使用保守的 64 bytes/pixel 加固定余量作准入估算，不是严格峰值保证。实际隔离进程仍需系统内存限额、磁盘预算与取消控制；复杂 FFT 尺寸的实际峰值和时长需测量。构建输出由 Git 忽略，默认插件发行脚本不会打包此 host 库。Colorsoft 效果、翻页性能和 ABI 尚未验证。
