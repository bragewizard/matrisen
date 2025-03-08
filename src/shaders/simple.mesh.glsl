#version 460
#extension GL_EXT_mesh_shader : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_buffer_reference : require

// #include "input_structures.glsl"

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
layout(triangles, max_vertices = 6, max_primitives = 2) out;

// layout(location = 0) out vec3 outNormal[];
// layout(location = 1) out vec3 outColor[];
// layout(location = 2) out vec2 outUV[];

// layout(push_constant) uniform constants {
//     mat4 render_matrix;
//     uvec2 padding;
// } PushConstants;

void main() {
    // uint vertexID = gl_LocalInvocationIndex;

    // vec3 positions[3] = vec3[](
    //     vec3(-0.5,  0.5, 0.0),  // Larger triangle for visibility
    //     vec3(-0.5, -0.5, 0.0),
    //     vec3( 0.5, -0.5, 0.0)
    // );

    // vec3 normals[3] = vec3[](vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0));
    // vec3 colors[3] = vec3[](vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0));
    // vec2 uvs[3] = vec2[](vec2(0.5, 1.0), vec2(0.0, 0.0), vec2(1.0, 0.0));

    // vec4 position = vec4(positions[vertexID], 1.0f);
    // vec4 worldPos = PushConstants.render_matrix * position;
    // gl_MeshVerticesEXT[vertexID].gl_Position = sceneData.viewproj * worldPos;  // Test with identity if needed
    SetMeshOutputsEXT(6, 2);
    gl_MeshVerticesEXT[0].gl_Position = vec4(-0.5, -0.5, 0.0, 1.0); // Bottom-left
    gl_MeshVerticesEXT[1].gl_Position = vec4(0.5, -0.5, 0.0, 1.0);  // Bottom-right
    gl_MeshVerticesEXT[2].gl_Position = vec4(0.0, 0.5, 0.0, 1.0);   // Top-center
    // gl_MeshVerticesEXT[vertexID].gl_Position = vec4(positions[vertexID], 1.0);  // Uncomment to bypass sceneData

    // outNormal[vertexID] = normals[vertexID];
    // outColor[vertexID] = colors[vertexID];  // Skip materialData for now
    // outUV[vertexID] = uvs[vertexID];

    // if (vertexID == 0) {
    //     gl_PrimitiveTriangleIndicesEXT[0] = uvec3(0, 1, 2);
    // }
}
