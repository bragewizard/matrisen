#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_mesh_shader : require // If linked to mesh shader pipeline

#include "input_structures.glsl"

// Input from the mesh shader (matches perVertex output)
layout (location = 0) in PerVertexData {
    vec3 normal;
    vec2 uv;
} inData;

// Output color
layout(location = 0) out vec4 outFragColor;

void main()
{
    // vec3 color = inData.normal * texture(colorTex, inData.uv).xyz;
    vec3 ambient = sceneData.ambientColor.xyz;
    // vec3 ambient = color;
    outFragColor = vec4(inData.normal + ambient ,1.0f);
    // outFragColor = vec4(inData.normal, 1.0);
}
