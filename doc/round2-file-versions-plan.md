# R2-05：可信文件版本展示与选择

已确认边界：保留原名/原路径。默认KOOBONE卷身份未经过版本关系验证，不自动
合并；只使用明确验证的适配器能力或CatalogStore已经验证的volume_id关系。

1. `library.lua`及library specs：建立显式identity_options接口，保存/离线恢复可信卷关系；忽略远端记录自己声明的verified字段。
2. `shelf_navigation.lua`及navigation specs：按可信volume_id枚举版本和正确卷计数；同名/同ID未验证仍返回一个独立文件。
3. `bookshelf.lua`及controller specs：详情传版本列表，选择后按账号/entry身份从当前目录重新解析；被删除/换账号版本拒绝动作。
4. `book_detail.lua`及detail specs：显示文件版本和实际本地路径；多版本提供原生选择菜单，选择只切换详情，不隐式下载、删除或重命名。
5. 全量Lua、语法、实际KOReader原生详情/版本菜单集成、review；记录真实版本关系尚待来源证据，提交推送。
