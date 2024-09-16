//GLSL version to use
#version 460

//size of a workgroup for compute
layout (local_size_x = 16, local_size_y = 16) in;

//descriptor bindings for the pipeline
layout(rgba16f,set = 0, binding = 0) uniform image2D image;

//push constants block
layout( push_constant ) uniform constants
{
   vec4 data1;
   vec4 data2;
   vec4 data3;
   vec4 data4;
} PushConstants;

void main() {
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(image);

    vec4 top_color = PushConstants.data1;
    vec4 bottom_color = PushConstants.data2;

    if (texel_coord.x < size.x && texel_coord.y < size.y) {
        float blend = float(texel_coord.y) / (size.y); 
        imageStore(image, texel_coord, mix(top_color, bottom_color, blend));
    }
}
