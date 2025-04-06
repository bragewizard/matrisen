#version 460 core
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

layout(location = 0) out vec3 outNormal;
layout(location = 1) out vec3 outColor;
layout(location = 2) out vec2 outUV;

void main()
{
    Entry object = resources.entries[1];
    Vertex v = scenedata.vertexbuffer.vertices[gl_VertexIndex];
    mat4 pose = scenedata.posebuffer.poses[object.pose_index];

    vec4 position = vec4(v.position, 1.0f);

    gl_Position = scenedata.viewproj * pose * position;
    // gl_Position = position;

    outNormal = (pose * vec4(v.normal, 0.f)).xyz;
    outColor = v.color.xyz;
    outUV.x = v.uv_x;
    outUV.y = v.uv_y;
}
