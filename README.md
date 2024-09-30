# vulkanguide-zig

Implementation of https://vkguide.dev in Zig.

## Used libraries
- Vulkan (obtained through `shell.nix`)
- [SD2](https://github.com/libsdl-org/SDL) (obtained through `shell.nix`)
- [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) (copy in `thirdparty/vma`)
- [cimgui](https://github.com/cimgui/cimgui) (git submodule)
- [cgltf](https://github.com/jkuhlmann/cgltf) (copy in `thirdparty/cgltf`)

## Build on linux
Update submodules:
```bash
$ git submodule update --init --recursive
```

Patch cimgui:
```bash
$ cd thirdparty/cimgui/imgui
$ git apply ../../../imgui.diff 
```
This is needed for imgui to export backend functions (SDL2 + Vulkan in this case).

Build shaders
```bash
$ glslc -fshader-stage=compute shaders/gradient.glsl -o gradient.spv
$ glslc -fshader-stage=compute shaders/sky.glsl -o sky.spv
$ glslc -fshader-stage=fragment shaders/metallic_frag.glsl -o metallic_frag.spv
$ glslc -fshader-stage=vertex shaders/metallic_vert.glsl -o metallic_vert.spv
```

Build and run
```bash
$ zig build run
```
