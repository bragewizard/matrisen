#version 460
#extension GL_EXT_mesh_shader : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

#include "input_structures.glsl"

layout(push_constant) uniform constants {
    mat4 render_matrix;
    uvec2 padding;
} PushConstants;

layout(local_size_x = 3, local_size_y = 1, local_size_z = 1) in;
layout(max_vertices = 64, max_primitives = 32) out;
layout(triangles) out;

layout(location = 0) out PerVertexData {
    vec3 normal;
    vec2 uv;
} perVertex[];

const vec3 vertices[3] = {
        vec3(-0.5, -0.5, 0),
        vec3(0, 0.5, 0),
        vec3(0.5, -0.5, 0)
    };
const vec3 normals[3] = {
        vec3(1.0, 0.0, 0.0),
        vec3(0.0, 1.0, 0.0),
        vec3(0.0, 0.0, 1.0)
    };

void main() {
    uint thread_id = gl_LocalInvocationID.x;
    perVertex[thread_id].normal = normals[thread_id];
    gl_MeshVerticesEXT[thread_id].gl_Position = sceneData.viewproj * PushConstants.render_matrix * vec4(vertices[thread_id], 1.0);
    if (thread_id == 0) {
        SetMeshOutputsEXT(3, 1);
        gl_PrimitiveTriangleIndicesEXT[thread_id] = uvec3(0, 1, 2);
    }
}
