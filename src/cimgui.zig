const imgui = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
    @cDefine("CIMGUI_USE_SDL2", "");
    @cDefine("CIMGUI_USE_VULKAN", "");
    @cInclude("cimgui_impl.h");
});
pub usingnamespace imgui;
