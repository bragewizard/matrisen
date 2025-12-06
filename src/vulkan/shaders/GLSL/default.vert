#version 460 core
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
// #extension GL_KHR_shader_draw_parameters : require // For gl_DrawID

struct Vertex {
    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec4 color;
};

layout(buffer_reference, scalar) readonly buffer Vertices { Vertex v[]; };
layout(buffer_reference, scalar) readonly buffer Indices { uint i[]; };

// --- SET 0: GLOBALS (Your SceneData) ---
layout(set = 0, binding = 0, std140) uniform SceneData {
    mat4 view;
    mat4 proj;
    mat4 viewproj;
    vec4 ambient_color;
    vec4 sun_direction;
    vec4 sun_color;
} scene; // <--- Accessed as 'scene.viewproj'

struct MeshData {
    Vertices vertexBuffer; // 64-bit address
    Indices  indexBuffer;  // 64-bit address
    // Bounding box, LOD info, etc. could go here
};

layout(set = 1, binding = 0, std140) readonly buffer MeshTable {
    MeshData meshes[];
} meshTable;

struct InstanceData {
    mat4 modelMatrix;
    uint meshIndex;
    uint materialIndex;
    uint _pad0;
    uint _pad1;
};

layout(set = 1, binding = 1, std140) readonly buffer InstanceTable {
    InstanceData instances[];
} instanceTable;

layout(location = 0) out vec3 outNormal;
layout(location = 1) out vec3 outColor;
layout(location = 2) out vec2 outUV;

// void main() {
//     // A. FETCH INSTANCE (Using Indirect Draw ID)
//     // In vkCmdDrawIndirect, the GPU increments gl_DrawID for each command in the buffer
//     InstanceData inst = instanceTable.instances[gl_DrawID];
//     // B. FETCH MESH (Indirection)
//     // We cast the u64 index down to uint for array access
//     MeshData mesh = meshTable.meshes[uint(inst.meshIndex)];
//     // C. FETCH VERTEX (Programmable Pulling)
//     // 1. Get the real index from the Index Buffer
//     uint index = mesh.indexBuffer.i[gl_VertexIndex];
//     // 2. Get the Vertex from the Vertex Buffer
//     Vertex v = mesh.vertexBuffer.v[index];
//     // D. TRANSFORM
//     // P * V * M * Position
//     gl_Position = scene.viewproj * inst.modelMatrix * vec4(v.position, 1.0);
//     // E. OUTPUTS
//     // Rotate the normal by the model matrix (ignoring translation)
//     outNormal = mat3(inst.modelMatrix) * v.normal; 
//     outColor = v.color.rgb;
//     outUV = vec2(v.uv_x, v.uv_y);
// }

void main()
{
    InstanceData inst = instanceTable.instances[gl_VertexIndex];
    MeshData mesh = meshTable.meshes[uint(inst.meshIndex)];
    uint index = mesh.indexBuffer.i[gl_VertexIndex];
    Vertex v = mesh.vertexBuffer.v[index];
    // 1. Define hardcoded triangle data
    // Vulkan Y-coordinate is down, so (0, -0.5) is top
    const vec3 positions[3] = vec3[3](
        vec3(0.0, -0.5, 0.0),
        vec3(0.5, 0.5, 0.0),
        vec3(-0.5, 0.5, 0.0)
    );

    const vec3 colors[3] = vec3[3](
        vec3(1.0, 0.0, 0.0), // Red
        vec3(0.0, 1.0, 0.0), // Green
        vec3(0.0, 0.0, 1.0)  // Blue
    );

    // 2. Use the built-in gl_VertexIndex to access the array
    // Note: This relies on vkCmdDraw(3, ...) being called
    vec3 pos = positions[gl_VertexIndex];
    // vec3 pos = positions[gl_DrawID];
    // 3. Output
    // gl_Position = vec4(v.position, 1.0); // if i use this it crashes
    gl_Position = vec4(pos, 1.0);
    
    outNormal = vec3(0.0, 0.0, 1.0);
    outColor = colors[gl_VertexIndex];
    outUV = vec2(0.0);
}
