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

layout(location = 0) in PerVertexData {
    vec4 color;
} inData;

layout(location = 0) out vec4 outColor;

void main() {
    outColor = inData.color;
    // outColor = vec4(0,0,0,1);
}
