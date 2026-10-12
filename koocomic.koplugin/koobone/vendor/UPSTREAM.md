# XML parser

`xml.lua` 原样复制 KOReader `v2026.07.1` 的 `plugins/newsdownloader.koplugin/lib/xml.lua`。

原作者 Paul Chakravarti，文件保留作者、历史和 Lua license 声明；此模块不依赖 newsdownloader 插件。EPUB 适配层拒绝 DTD，不读取外部实体，不重写 XHTML/OPF 内容。该解析器不提供完整 XML namespace/schema 验证，因此资源定位之外的语义仍由 EPUB 输出验证及真实 KOReader 打开测试覆盖。
