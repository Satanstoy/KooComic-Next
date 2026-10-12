package.path = "./koocomic.koplugin/?.lua;" .. package.path
local ok, Layout = pcall(require, "koobone.ui.shelf_layout")
assert(ok, "Bookshelf-aligned adaptive layout is missing")
for _, size in ipairs({{600,800},{758,1024},{800,600},{1024,758}}) do
    for _, scale in ipairs({1, 1.28}) do
        local layout = Layout.compute{width=size[1],height=size[2],scale=scale,path=true}
        assert(layout.header.h >= 40*scale and layout.footer.h >= 40*scale)
        assert(layout.card_w >= 120*scale and layout.rows >= 1)
        local last = 0
        for _, rect in ipairs(layout.slots) do
            assert(rect.x >= 0 and rect.y >= layout.header.h)
            assert(rect.x+rect.w <= size[1] and rect.y+rect.h <= layout.footer.y)
            if rect.y == last then assert(rect.x >= 0) end
            last = rect.y
        end
        assert(layout.footer.y+layout.footer.h == size[2])
        assert(layout.columns*layout.rows == #layout.slots)
    end
end
print("shelf layout spec: OK")
