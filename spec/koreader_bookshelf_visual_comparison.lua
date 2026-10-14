-- Same-resource comparison against actual pinned upstream modules, not mocks.
require("setupkoenv")
local root,reference=assert(arg[1]),assert(arg[2])
package.path=root.."/koocomic.koplugin/?.lua;"..reference.."/?.lua;"..package.path
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):wrap{sdl_window={width=600,height=800},dev_no_c_blitter=false}
local Device=require("device");require("document/canvascontext"):init(Device)
local BB=require("ffi/blitbuffer")
local Image=require("ui/widget/imagewidget")
local Spine=require("lib/bookshelf_spine_widget")
local UpFolder=require("lib/bookshelf_folder_card")
local Folder=require("koobone.ui.vendor.bookshelf.folder_card")
local Cover=require("koobone.ui.vendor.bookshelf.cover_card")
local Settings=require("lib/bookshelf_settings_store")
require("lib/bookshelf_fonts").setUIFontFace(nil)
local ffi=require("ffi")
local directory="/tmp/koocomic-bookshelf-comparison-"..tonumber(ffi.C.getpid())
assert(require("koobone.preprocess_files"):new{roots={directory}}:mkdir(directory))
local source=BB.new(178,258,BB.TYPE_BBRGB32);source:fill(BB.COLOR_WHITE)
source:paintRectRGB32(0,0,178,128,BB.colorFromString("#38836c"))
source:paintRectRGB32(0,138,178,120,BB.colorFromString("#c2446a"))
local function image() return Image:new{image=source:copy(),image_disposable=true,scale_factor=1} end
local comparisons=0
for _,size in ipairs({16,20}) do
    Settings.save("stack_label_font_scale",size/16*100)
    for _,format in ipairs({{name="gray",kind=BB.TYPE_BB8},{name="rgb",kind=BB.TYPE_BBRGB32}}) do
        for _,night in ipairs({false,true}) do
            Device.screen.night_mode=night
            local spine=Spine:new{width=184,height=264,book={title="Same cover"},show_progress=false,show_status=false}
            local upstream=spine:_wrapCoverInCard(image(),180,260,1)
            local actual=spine._cover_card
            local imported=Cover.RoundedCornerCard:new{inner=image(),width=180,height=260,
                radius=actual.radius,border_size=actual.border_size,border_color=actual.border_color or require("lib/bookshelf_cover_progress").resolvedColors().border,
                bg_color=actual.bg_color,shadow_color=actual.shadow_color,shadow_offset_x=actual.shadow_offset_x,
                shadow_offset_y=actual.shadow_offset_y,shadow_radius=actual.shadow_radius}
            local buffers={BB.new(184,264,format.kind),BB.new(184,264,format.kind)}
            for _,buffer in ipairs(buffers) do buffer:fill(BB.COLOR_WHITE) end
            actual:paintTo(buffers[1],0,0);imported:paintTo(buffers[2],0,0)
            for y=0,263 do for x=0,183 do
                local a,b=buffers[1]:getPixel(x,y):getColorRGB32(),buffers[2]:getPixel(x,y):getColorRGB32()
                assert(a.r==b.r and a.g==b.g and a.b==b.b,"cover kernel mismatch at "..x..","..y)
            end end
            local up_folder,up_label,up_floor=UpFolder.build{width=184,height=264,label="Same Original Series",shadow_reserve=4}
            local polygon=up_folder[1]
            local folder,label,floor=Folder.build{width=184,height=264,label="Same Original Series",shadow_reserve=4,
                face=up_label[1].face,bold=up_label[1].bold,font_size=size,theme={folder_bg=polygon.fill_color,border=polygon.edge_color,folder_fg=up_label[1].fgcolor}}
            assert(floor==up_floor,"folder silhouette geometry must match upstream")
            up_folder:paintTo(buffers[1],0,0);up_label:paintTo(buffers[1],0,0)
            folder:paintTo(buffers[2],0,0);label:paintTo(buffers[2],0,0)
            local differences=0
            for y=0,263 do for x=0,183 do
                local a,b=buffers[1]:getPixel(x,y):getColorRGB32(),buffers[2]:getPixel(x,y):getColorRGB32()
                if a.r~=b.r or a.g~=b.g or a.b~=b.b then differences=differences+1 end
            end end
            assert(differences==0,"same-resource imported cover/folder pixels differ: "..differences.." upstream bold="..tostring(up_label[1].bold))
            local combined=BB.new(400,280,format.kind);combined:fill(BB.COLOR_WHITE)
            combined:blitFrom(buffers[1],8,8,0,0,184,264);combined:blitFrom(buffers[2],208,8,0,0,184,264)
            if night then combined:invert() end
            assert(combined:writeToFile(directory.."/"..size.."-"..format.name.."-"..tostring(night)..".png","png"))
            for _,buffer in ipairs(buffers) do buffer:free() end
            combined:free();up_folder:free();up_label:free();folder:free();label:free();imported:free();upstream:free();spine:free()
            comparisons=comparisons+1
        end
    end
end
source:free();Device.screen.night_mode=false;Device:exit()
print("Actual upstream / imported same-cover folder comparison: OK "..comparisons.." pixel-identical pairs "..directory)
