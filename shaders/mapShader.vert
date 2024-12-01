#version 450

layout(push_constant) uniform MapPushConstants
{
    int width;
    int height;
    //int terrains_count;
    //int textureMasks_count;
} mapPushConstants;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;

layout(set = 0, binding = 0) uniform CameraBufferObject
{
    mat4 view;
    mat4 proj;
}
ubo;

layout(location = 0) out vec2 UV;
layout(location = 1) out vec3 UVW;
layout(location = 2) out vec3 dxyz;
layout(location = 3) out vec3 normal;

uint textureSize = 512;
uint texelsPerMeter = 32;
void main()
{
    normal = inNormal;
    dxyz.x = abs(normal.x);
    dxyz.y = abs(normal.y);
    dxyz.z = abs(normal.z);
    dxyz /= (dxyz.x+dxyz.y+dxyz.z);
    gl_Position = ubo.proj * ubo.view * vec4(inPosition, 1.0);
    UV = vec2((inPosition.x+mapPushConstants.width/2)/mapPushConstants.width, (inPosition.y+mapPushConstants.height/2)/mapPushConstants.height);
    UVW = inPosition/(textureSize/texelsPerMeter);//(textureSize/texelsPerMeter)
}
