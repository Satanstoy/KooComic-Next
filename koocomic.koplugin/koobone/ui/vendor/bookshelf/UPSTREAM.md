# Bookshelf 绘制复用

来源：AndyHazz/bookshelf.koplugin，固定 commit `2c8bfd8e53b73b24232e674e12ebc6168963aef5`，AGPL-3.0 许可证保存在本目录。

- `grid_margins.lua`：原样复制 `lib/bookshelf_grid_margins.lua`。
- `space.lua`：原样复制 `lib/bookshelf_space.lua`。
- `folder_polygon.lua`：提取 `lib/bookshelf_folder_card.lua` 的 L 形文件夹绘制方法；尺寸、颜色、圆角和边线改由实例参数提供，不加载 Bookshelf 的设置、字体、进度、缓存或夜间模式单例。
- `folder_card.lua`：复制 `lib/bookshelf_folder_card.lua` 的文件夹绘制和文本测量主体；使用显式 theme/face，保留索引耳、字体行高测量、两行截断、RGB32绘制和 Android inversion 修复。不去除系列名称末尾 `/`。移除上游主题/夜间注册器与设置读取，KooComic 负责重建。
- `count_badge.lua`：复制 `lib/bookshelf_count_badge.lua`；保留字形间距、原生FrameContainer、圆角及内边距，UTF-8字节使用Lua 5.1兼容的十进制转义。字体、主题和数量由调用方传入，不读取已读计数或注册上游回调。
- `cover_card.lua`：提取 `lib/bookshelf_spine_widget.lua:82` 的颜色安全边线、`:563` 的CornerKeep及RoundedCornerCard主体；保留实际背景角落恢复、RGB32边线及Android反转修复。移除壁纸查询、主题/设置单例；阴影颜色由实例提供。硬阴影以原生圆角矩形绘制，未引入上游壁纸混色及阅读状态装饰。

v0.4 的生产网格已改用完整 `folder_card.lua`，旧 `folder_polygon.lua` 仅保留历史实现，不再参与正式卡片。原生颜色、灰阶/夜间与双插件整体体验仍须按 NV-25 验收；本次不声称继承上游的全局夜间回调。

- `stack_display.lua`：从固定 `lib/bookshelf_stack_display.lua` 提取六模式语义、外部标签规则、ribbonInset/ribbonWidget、pileLayers/pileStep/pileInset和collagePlacement。缎带保留字体测量、两行截断、底部间隔和外伸几何；字体/颜色显式注入，不去除系列名末尾`/`。不引入上游设置、仓库、壁纸、全局夜间解析器或collageBB；KooComic用各自拥有的ImageWidget构成稳定四分格，缺图使用占位背景，未实现上游基于图像调色板的填充。叠放采用上游数量/方向/间距，背景层用KOReader FrameContainer适配，不宣称原样复用其主题混色算法。
- `../bookshelf_icons.lua`：参考 `bookshelf_chip_bar.lua:_iconFace` 与 `bookshelf_widget.lua` 的搜索/返回glyph，统一使用KOReader已自带的`symbols`字体，不复制字体文件。菜单与翻页采用同字体的FontAwesome glyph，而非上游手绘菜单条；这是显式的紧凑图标适配，避免旧IconWidget默认尺寸撑满触控区域。

全部模块使用 KooComic 独立命名空间；上层使用自己的目录 DTO，不向上游全局 `lib/*` 模块写入兼容别名。功能仅来自有署名的源码适配，不以此声明完整 Bookshelf 的 UI/运行时被复制。
