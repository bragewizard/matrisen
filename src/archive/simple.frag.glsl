#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_mesh_shader : require // If linked to mesh shader pipeline

#include "input_structures.glsl"

// Input from the mesh shader (matches perVertex output)
layout (location = 0) in PerVertexData {
    vec3 worldpos;
    vec3 normal;
    vec2 uv;
} inData;

layout(location = 0) out vec4 outColor;

void main() {
    vec3 white = vec3(0.05, 0.05, 0.05);
    vec3 black = vec3(0.08, 0.08, 0.08);

    float gridSize = 5.1;
    float r = length(inData.worldpos) * 0.05;
    float x = floor(inData.worldpos.x / gridSize);
    float y = floor(inData.worldpos.y / gridSize);
    
    // Checker pattern calculation
    float checker = mod(x + y, 2.0);
    vec3 color = (checker == 0.0) ? white : black;
  
    outColor = vec4(color, 1.0);
}
