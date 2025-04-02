#version 460 core
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_mesh_shader : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_shader_explicit_arithmetic_types_float16 : require

// Make sure this include defines SceneData with separate view and proj matrices
#include "input_structures.glsl"

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
layout(triangles, max_vertices = 4, max_primitives = 2) out;

// Output can be minimal if no fragment shader processing needed
// layout (location = 0) out vec3 v_color; // Example if passing color

layout(location = 0) out PerVertexData {
    vec4 color;
} perVertex[];

struct Line {
    vec3 p0;
    float thicknes;
    vec3 p1;
    uint color;
};

layout(buffer_reference, std430) readonly buffer LinePrimitiveData {
    Line lines[];
};

// Push constants block - Simplified
layout(push_constant) uniform constants {
    mat4 model;
    LinePrimitiveData address;
} pc;

void main() {
    // --- Data Fetch (Invocation 0 could optimize this later) ---
    Line line = pc.address.lines[gl_WorkGroupID.x];

    // 1. Calculate ModelView matrix
    mat4 modelView = sceneData.view * pc.model;

    // 2. Transform line endpoints to View Space
    //    (Assuming standard matrices where w=1 initially)
    vec3 p0_view = (modelView * vec4(line.p0, 1.0)).xyz;
    vec3 p1_view = (modelView * vec4(line.p1, 1.0)).xyz;

    // 3. Calculate line direction in View Space
    vec3 lineDir_view = p1_view - p0_view;
    float lineLengthSq = dot(lineDir_view, lineDir_view);

    // Handle degenerate lines (zero length)
    if (lineLengthSq < 0.00001) {
        if (gl_LocalInvocationID.x == 0) {
            SetMeshOutputsEXT(0, 0); // Output nothing for zero-length lines
        }
        return; // Stop processing for this invocation
    }
    lineDir_view = normalize(lineDir_view);

    // 4. Calculate direction from line towards camera (origin in View Space)
    //    Using the midpoint of the line for stability, but p0_view often works too.
    vec3 lineMid_view = (p0_view + p1_view) * 0.5;
    vec3 viewDir = normalize(-lineMid_view); // Vector from line midpoint TO camera origin

    // 5. Calculate the offset direction using cross product
    //    This direction is perpendicular to both the line and the view vector,
    //    effectively "rolling" the quad to face the camera.
    vec3 offsetDir_view = normalize(cross(lineDir_view, viewDir));

    // 6. Handle edge case: Line points directly at/away from the camera
    //    If lineDir and viewDir are parallel, cross product is zero.
    //    We need a fallback orientation - using view space 'up' (0,1,0) is common.
    if (dot(offsetDir_view, offsetDir_view) < 0.0001) { // Check if cross product is near zero
        vec3 up_view = vec3(0.0, 1.0, 0.0); // Assuming standard view matrix convention
        offsetDir_view = normalize(cross(lineDir_view, up_view));
        // Handle another edge case: line is parallel to 'up'
        if (dot(offsetDir_view, offsetDir_view) < 0.0001) {
            vec3 right_view = vec3(1.0, 0.0, 0.0);
            offsetDir_view = normalize(cross(lineDir_view, right_view));
        }
    }

    // 7. Calculate half thickness offset vector
    vec3 halfOffset_view = offsetDir_view * line.thicknes * 0.1;

    // --- Set Mesh Output Count (only invocation 0) ---
    if (gl_LocalInvocationID.x == 0) {
        SetMeshOutputsEXT(4, 2); // 4 vertices, 2 triangle primitives
    }

    // Optional Barrier: Only needed if optimizing with shared memory later.
    // barrier();

    // --- Vertex Generation (first 4 invocations) ---
    if (gl_LocalInvocationID.x < 4) {
        vec3 base_pos_view;
        float offset_sign;

        uint color = line.color; // 32-bit RGBA8
        float a = float((color >> 24) & 0x000000FF) / 255.0;
        float b = float((color >> 16) & 0x000000FF) / 255.0;
        float g = float((color >> 8) & 0x000000FF) / 255.0;
        float r = float(color & 0x000000FF) / 255.0;

        // Calculate fade factor based on distance
        float distance = length(lineMid_view) / 10; // Distance from camera to line midpoint

        // Alternative: Use viewDir.z (negative, so invert and scale)
        // float fadeFactor = clamp(-viewDir.z / 10.0, 0.0, 1.0); // Adjust 10.0 as needed

        // Apply fade to alpha

        // Repack the color
        vec4 fadedColor = vec4(r,g,b,a);
        perVertex[gl_LocalInvocationID.x].color = fadedColor;

        // Determine base view position and offset sign
        if (gl_LocalInvocationID.x < 2) { // Vertices near p0
            base_pos_view = p0_view;
        } else { // Vertices near p1
            base_pos_view = p1_view;
        }

        if (gl_LocalInvocationID.x == 0 || gl_LocalInvocationID.x == 2) { // '-' side
            offset_sign = -1.0;
        } else { // '+' side (ID 1 or 3)
            offset_sign = 1.0;
        }

        // Calculate final vertex position in View Space
        vec3 final_pos_view = base_pos_view + halfOffset_view * offset_sign;

        // Project View Space position to Clip Space
        gl_MeshVerticesEXT[gl_LocalInvocationID.x].gl_Position = sceneData.proj * vec4(final_pos_view, 1.0);

        // Example: Output color (adjust as needed)
        // v_color[gl_LocalInvocationID.x] = vec3(1.0, 0.0, 1.0); // Magenta
    }

    // --- Primitive Assembly (only invocation 0) ---
    if (gl_LocalInvocationID.x == 0) {
        // Define 2 triangles forming the quad (check winding order for culling)
        // 0: p0 - offset | 1: p0 + offset | 2: p1 - offset | 3: p1 + offset
        gl_PrimitiveTriangleIndicesEXT[0] = uvec3(0, 2, 1); // (p0-, p1-, p0+)
        gl_PrimitiveTriangleIndicesEXT[1] = uvec3(1, 2, 3); // (p0+, p1-, p1+)
        // Alternate if culling is wrong:
        // gl_PrimitiveTriangleIndicesEXT[0] = uvec3(0, 1, 2);
        // gl_PrimitiveTriangleIndicesEXT[1] = uvec3(1, 3, 2);
    }
}
