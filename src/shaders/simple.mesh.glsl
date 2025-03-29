#version 460
#extension GL_EXT_mesh_shader : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

#include "input_structures.glsl"

layout(push_constant) uniform constants {
    mat4 render_matrix;
    uvec2 padding;
} PushConstants;

layout(local_size_x = 4, local_size_y = 1, local_size_z = 1) in;
layout(max_vertices = 4, max_primitives = 2) out;
layout(triangles) out;

layout(location = 0) out PerVertexData {
    vec3 worldpos;
    vec3 normal;
    vec2 uv;
} perVertex[];

const vec3 vertices[4] = {
    vec3(-1000, -1000, 0),  // Bottom-left
    vec3( 1000, -1000, 0),  // Bottom-right
    vec3(-1000,  1000, 0),  // Top-left
    vec3( 1000,  1000, 0)   // Top-right
};

const vec3 normals[4] = {
    vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 1.0),
    vec3(0.0, 0.0, 1.0)
};

const vec2 uvs[4] = {
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(0.0, 1.0),
    vec2(1.0, 1.0)
};

void main() {
    uint thread_id = gl_LocalInvocationID.x;
    perVertex[thread_id].normal = normals[thread_id];
    perVertex[thread_id].uv = uvs[thread_id];
    perVertex[thread_id].worldpos = vertices[thread_id];
    gl_MeshVerticesEXT[thread_id].gl_Position = sceneData.viewproj * PushConstants.render_matrix * vec4(vertices[thread_id], 1.0);
    
    if (thread_id == 0) {
        SetMeshOutputsEXT(4, 2);
        gl_PrimitiveTriangleIndicesEXT[0] = uvec3(0, 1, 2); // First triangle
        gl_PrimitiveTriangleIndicesEXT[1] = uvec3(1, 3, 2); // Second triangle
    }
}
