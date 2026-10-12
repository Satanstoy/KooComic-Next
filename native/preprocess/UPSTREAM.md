# 原生单页滤波原型

固定来源：[Euphoriyy/derainbowify.koplugin](https://github.com/Euphoriyy/derainbowify.koplugin/tree/f2892a219da65bd765d34ae2140a5dd706dfc42b)，commit `f2892a219da65bd765d34ae2140a5dd706dfc42b`。

`vendor/moire_filter_kissfft.c` 与 `vendor/kissfft/` 从上游同名路径原样复制；上游 GPL-3.0 保存在 `vendor/DERAINBOWIFY_LICENSE`，KissFFT 自带 `COPYING` 保留。新增 `filter.c` 包装输入与预算检查、错误返回和清理，不改变上游的频率掩模。上游原始入口仍存在，调用方只允许调用经过检查的 `koocomic_filter`。

此原型处理已经解码并准备好尺寸的灰阶/RGBX 单页，不负责 EPUB、JPEG/PNG 编解码或任务进程管理。只接受正偶数尺寸和连续 stride；奇数页面需由未来页适配器验证后补边并裁回，不能直接送入滤波器。

检查入口为 `int koocomic_filter(unsigned char *data, int width, int height, int stride, int is_colored, float strength, size_t memory_budget, size_t data_size)`；调用方必须提供真实可访问缓冲区的字节数，不得仅按页面声明尺寸估算。

```bash
make -C native/preprocess
python3 spec/native_preprocess_spec.py
```

目标交叉编译命令形式：`make -C native/preprocess TARGET=kindlehf CC=arm-kindlereader-linux-gnueabihf-gcc CFLAGS='-O2 -Wall -Wextra -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard'`。工具链前缀与 ABI 必须依据对应 KOReader koxtoolchain 发行版实测，不把此形式当作已经成功构建的设备包；检查 `file`、`readelf -h/-d`、导出符号及设备加载结果后才允许打包。

`memory_budget` 使用保守的 64 bytes/pixel 加固定余量作准入估算，不是严格峰值保证。实际隔离进程仍需系统内存限额、磁盘预算与取消控制；复杂 FFT 尺寸的实际峰值和时长需测量。构建输出由 Git 忽略，默认插件发行脚本不会打包此 host 库。Colorsoft 效果、翻页性能和 ABI 尚未验证。
