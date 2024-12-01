#version 450
// #extension GL_EXT_nonuniform_qualifier : require

layout(push_constant) uniform MapPushConstants
{
    uint width;
    uint height;
    //int terrains_count;
    //int textureMasks_count;
} mapPushConstants;

layout(location = 0) in vec2 UV;
layout(location = 1) in vec3 UVW;
layout(location = 2) in vec3 d;
layout(location = 3) in vec3 inNormal;

layout(set = 1, binding = 1) uniform sampler2D groundColor[8];
layout(set = 1, binding = 2) uniform sampler2D cliffColor[8];
layout(set = 1, binding = 3) uniform sampler2D groundNormal[8];
layout(set = 1, binding = 4) uniform sampler2D cliffNormal[8];
layout(set = 1, binding = 5) uniform sampler2D splatmaps[2];

layout(location = 0) out vec4 outColor;

vec3 lightDirection = vec3(0, 0, 1);
void main()
{
    vec3 normalVertex = normalize(inNormal);
//     vec3 outNormal = vec3(0, 0, 0);
    outColor = vec4(0.0, 0.0, 0.0, 1.0);
//     vec3 normal;
    vec4 color;
    vec4 splat_alpha;
    splat_alpha = texture(splatmaps[0], UV);
    for(uint i = 0; i < 4; i+=1)
    {
        if(splat_alpha[i] > 0)
        {
            color = texture(cliffColor[i], UVW.yz)*d.x + texture(cliffColor[i], UVW.xz)*d.y + texture(groundColor[i], UVW.xy)*d.z;
            color *= splat_alpha[i];
            outColor += color;
        }
//         color = texture(cliffColor[i], UVW.yz)*d.x + texture(cliffColor[i], UVW.xz)*d.y + texture(groundColor[i], UVW.xy)*d.z;
//         color *= splat_alpha[i];
//         outColor += color;

//         normal = texture(cliffNormal[i], UVW.yz).xyz*d.x + texture(cliffNormal[i], UVW.xz).xyz*d.y + texture(groundNormal[i], UVW.xy).xyz*d.z;
//         normal *= splat_alpha[i];
//         outNormal += normal;
    }
    splat_alpha = texture(splatmaps[1], UV);
    for(uint i = 0; i < 4; i+=1)
    {
        if(splat_alpha[i] > 0)
        {
            color = texture(cliffColor[i+4], UVW.yz)*d.x + texture(cliffColor[i+4], UVW.xz)*d.y + texture(groundColor[i+4], UVW.xy)*d.z;
            color *= splat_alpha[i];
            outColor += color;
        }
//         color = texture(cliffColor[i+4], UVW.yz)*d.x + texture(cliffColor[i+4], UVW.xz)*d.y + texture(groundColor[i+4], UVW.xy)*d.z;
//         color *= splat_alpha[i];
//         outColor += color;
        
//         normal = texture(cliffNormal[i+4], UVW.yz).xyz*d.x + texture(cliffNormal[i+4], UVW.xz).xyz*d.y + texture(groundNormal[i+4], UVW.xy).xyz*d.z;
//         normal *= splat_alpha[i];
//         outNormal += normal;
    }
//     outNormal = normalize(outNormal);

//     vec4 splat_alpha = texture(splatmaps[0], UV);
//     for(uint i = 0; i < 4; i+=1)
//     {
//         outColor += texture(layers[i], UVW.xy)*splat_alpha[i];
//     }
//     splat_alpha = texture(splatmaps[1], UV);
//     for(uint i = 0; i < 4; i+=1)
//     {
//         outColor += texture(layers[i+4], UVW.xy)*splat_alpha[i];
//     }
    
//     outColor = texture(cliffTextures[5], UVW.yz)*d.x + texture(cliffTextures[5], UVW.xz)*d.y + texture(groundTextures[0], UVW.xy)*d.z;
//     outColor *= dot(lightDirection, normal);
//     normalVertex = normalize(normalVertex+outNormal);
    outColor *= abs(normalVertex.z);
}
