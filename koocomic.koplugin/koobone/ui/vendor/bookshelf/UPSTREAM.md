# Bookshelf 绘制复用

来源：AndyHazz/bookshelf.koplugin，固定 commit `2c8bfd8e53b73b24232e674e12ebc6168963aef5`，AGPL-3.0 许可证保存在本目录。

- `grid_margins.lua`：原样复制 `lib/bookshelf_grid_margins.lua`。
- `space.lua`：原样复制 `lib/bookshelf_space.lua`。
- `folder_polygon.lua`：提取 `lib/bookshelf_folder_card.lua` 的 L 形文件夹绘制方法；尺寸、颜色、圆角和边线改由实例参数提供，不加载 Bookshelf 的设置、字体、进度、缓存或夜间模式单例。

全部模块使用 KooComic 独立命名空间；上层使用自己的目录 DTO，不向上游全局 `lib/*` 模块写入兼容别名。功能仅来自有署名的源码适配，不以此声明完整 Bookshelf 的 UI/运行时被复制。
