# Bookshelf 同资源离机对照

日期：2026-10-14。参考源码固定为 AndyHazz/bookshelf.koplugin
`2c8bfd8e53b73b24232e674e12ebc6168963aef5`；运行时为官方 KOReader
Linux `v2026.07.1`。不读取用户漫画或 Bookshelf 个人设置。

## 对照方法

`spec/koreader_bookshelf_visual_comparison.lua` 直接加载参考源码的真实
`SpineWidget` 与 `FolderCard`，同时加载正式 KooComic 的导入组件。
使用同一生成封面（绿/玫红色块）、相同 180×260 封面及 184×264 槽位、
相同原始系列标签、两种字体尺寸、灰阶/RGB 和日/夜逻辑状态。
上游解析出的配色与字体作为显式参数传给导入组件，不注入上游模块 mock。
逐像素验证封面轮廓、边框、文件夹轮廓和标签：8 组组件配对零差异。
每组导出左右并列 PNG，左侧 Bookshelf，右侧 KooComic。

正式 KooComic 整页另由 `koreader_ui_matrix_integration.lua` 验证：四种
竖横屏、两种字号、两种像素格式、日夜逻辑状态，13 种视图，共 416 帧；
检查非空像素、长标题边界、关闭图片缓冲和反复开关 FD。
管理与详情另外覆盖 64 帧。逻辑反色不等于 Colorsoft 物理夜间刷新。

## 有意保留的差异

| 部分 | KooComic 行为 | 原因 |
|---|---|---|
| 数据源与分类 | 系列、卷、已下载 | 云端漫画目录，不复制 Bookshelf 本地作者/类型等分类 |
| 顶栏 | 返回、搜索、菜单，统一原生符号 | 维持已批准的漫画工作流，不复制上游首页 hero/阅读统计 |
| 状态与计数 | 下载、处理、选择计数及批量动作 | 漫画任务状态，不套用阅读进度或收藏状态 |
| 六种系列形式 | 文件夹、缎带、叠放、拼贴、文字、封面 | 沿用上游形式；拼贴配色与部分构图是轻量适配，非整模块复制 |
| 字体/主题设置 | 显式 KooComic 设置 | 不读取或修改 Bookshelf 单例，两个插件可独立使用 |
| 背景及动态主题 | 简洁书架背景，视图重建应用主题 | 未复制上游 wallpaper、封面开启动画与全部主题编辑器 |
| 原始标题及版本 | 保持 KOOBONE 名称，可信关系才合并 | 不为 UI 美观重命名或臆造远端关系 |

零像素差异仅针对固定参数的复用组件，不宣称两个插件整页完全相同。
整页结构、六样式及上述业务差异以批准的工程 spec 为准。实际同时装载、
扫描、原生 EPUB 提供器打开和双向删除另外由 coexistence 集成测试覆盖；
并不声称已经点过 Colorsoft 上 Bookshelf 的阅读按钮。

## 五种状态整页证据

`koreader_bookshelf_screen_comparison.lua` 用真实 EPUB 写入相同封面和系列
元数据，真实 BookInfoManager 提取、Repo 扫描、BookshelfWidget 绘制；参考端
通过正常设置收起 Hero、使用封面模式和文件夹形式，不缩放 Hero 截图。
当前稿为 Git 导出 `b598f98` 的真实 KooComic；目标参考为固定上游的实际原生
重绘，不是宣称产品应逐像素复制整页；实施后采用 `ed769dd` 的正式 UI 代码。
三者采用同屏幕、方向、默认字号和相同生成图片，均是测试资源，不是真实账号。
四种方向尺寸共保存 60 张 PNG 于 `assets/bookshelf-alignment/`。

| 状态（600×800 示例） | 当前 | 目标参考重绘 | 实施后 |
|---|---|---|---|
| 系列首页 | [current](assets/bookshelf-alignment/600x800-current-series.png) | [target](assets/bookshelf-alignment/600x800-target-series.png) | [final](assets/bookshelf-alignment/600x800-final-series.png) |
| 系列内页 | [current](assets/bookshelf-alignment/600x800-current-inside-series.png) | [target](assets/bookshelf-alignment/600x800-target-inside-series.png) | [final](assets/bookshelf-alignment/600x800-final-inside-series.png) |
| 全部单卷 | [current](assets/bookshelf-alignment/600x800-current-volumes.png) | [target](assets/bookshelf-alignment/600x800-target-volumes.png) | [final](assets/bookshelf-alignment/600x800-final-volumes.png) |
| 搜索 | [current](assets/bookshelf-alignment/600x800-current-search.png) | [target](assets/bookshelf-alignment/600x800-target-search.png) | [final](assets/bookshelf-alignment/600x800-final-search.png) |
| 多选 | [current](assets/bookshelf-alignment/600x800-current-selected.png) | [target](assets/bookshelf-alignment/600x800-target-selected.png) | [final](assets/bookshelf-alignment/600x800-final-selected.png) |

800×600、758×1024、1024×758 使用同样命名。原生像素断言确保每帧出现
输入封面的绿色及玫红色块；文件夹允许按设计遮盖封面下半，因此只要求露出上半。
系列内和搜索的路径文字、已下载标签、底栏任务入口是上表列明的业务差异。
参考与产品外部留白、卡片尺寸和标题粗细有小幅差异，保留已批准的紧凑漫画 UI；
不把这种有意适配记录成像素一致。

## UI-24 逐项检查

| 要求 | 离机结果与依据 |
|---|---|
| 文件夹轮廓及数量徽标清晰 | 通过：实际 series 截图，文件夹/标签组件逐像素对照；下载数量为新增业务徽标 |
| 封面比例及完整图片 | 通过：三栏竖屏/四栏横屏，原生 ImageWidget contain；四方向五态有封面像素断言；标签遮挡是有意设计 |
| 分类条与单行页脚 | 通过：五态整页截图；选择在既有页脚替换命令，不增加永久第二排 |
| 标题最多两行、详情完整名称 | 通过：原生 TextBoxWidget 高度限额；416 帧长中英文及64帧详情/管理几何检查 |
| 无相邻内容或触控区域误遮挡 | 通过：四方向实际绘制、几何断言与PNG检查；浮层徽标与选中边框属允许覆盖 |
| 图标名称可达 | 通过：原生符号统一，长按名称、返回/搜索/菜单回调及控制器测试 |
| 禁用态与选择态区分 | 通过：无上一页/下一页灰显；多选边框和计数，原生 selected 图与选择测试 |

阅读补充：coexistence 测试现通过真正 PluginLoader 发现两插件，ReaderUI
注册实际实例；上游 `_openBook` 和 KooComic `Downloader:open` 都真正打开
生成 EPUB，再调用真实 `ReaderUI:onClose`，断言返回各自可见书架、实例清空和
document 释放。两种初始顺序均通过。设备按钮触控和物理刷新仍不在此证据范围。
