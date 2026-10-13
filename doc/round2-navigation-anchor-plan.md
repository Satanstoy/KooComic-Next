# R2-02：刷新稳定身份定位

已确认方案：只在目录刷新和屏幕重排时定位旧页面首条稳定身份；搜索、筛选、
切换视图继续使用既有页码记忆。条目消失则夹取原页码，不凭同名猜身份。
系列使用已归一化系列key，卷使用账号/卷/文件版本key；换账号不能带入锚点。

1. `spec/shelf_navigation_spec.lua`：同名不同版本key不同，系列刷新key稳定，换账号key不同；先红再在Navigation添加rowKey。
2. `spec/bookshelf_grid_spec.lua`：刷新前插入/删除导致分页位移，首条身份仍在当前页；消失回退合法页码，旋转后定位。Grid仅用传入row_key，不根据标题合并。
3. `spec/shelf_controller_spec.lua`：实际异步刷新传递preserve_anchor，普通搜索/筛选不带此标志；Bookshelf.show在账号不变时才允许定位。
4. 官方KOReader原生管理页回归、43组Lua与语法检查；独立review、补规格证据后提交推送。
