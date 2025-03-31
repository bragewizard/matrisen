#version 460

#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_mesh_shader : require // If linked to mesh shader pipeline

#include "input_structures.glsl"

layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(0.02 , 0.02, 0.02, 0.5);
}
