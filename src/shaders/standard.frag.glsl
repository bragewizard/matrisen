#version 460
#extension GL_EXT_buffer_reference : require

struct Vertex {
    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec4 color;
};

struct Entry {
    uint pose_index;
    uint object_index;
    uint vertex_index;
};

layout(buffer_reference, std430) readonly buffer Vertices { Vertex vertices[]; };

layout(buffer_reference, std430) buffer Poses { mat4 poses[]; };

layout(set = 0, binding = 0) uniform SceneData {
    mat4 view;
    mat4 proj;
    mat4 viewproj;
    vec4 ambient_color;
    vec4 sun_direction;
    vec4 sun_color;
    Poses posebuffer;
    Vertices vertexbuffer;
} scenedata;

layout(set = 1, binding = 0) readonly buffer ResourceTable { Entry entries[]; } resources;

layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec2 inUV;

layout(location = 0) out vec4 outFragColor;

void main()
{
    float lightValue = max(dot(inNormal, scenedata.sun_direction.xyz), 0.1f);

    vec3 color = inColor;
    vec3 ambient = color * scenedata.ambient_color.xyz;

    // outFragColor = vec4(color * lightValue * sceneData.sunlightColor.w + ambient, 1.0f);
    
    vec3 normalColor = normalize(inNormal) * 0.5 + 0.5;
    outFragColor = vec4(normalColor, 1.0);
    // outFragColor = vec4(1.0,1.0,1.0,1.0); 
}
