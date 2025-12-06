const std = @import("std");
const m = @import("matrisen");
const log = std.log.scoped(.main);
const Core = m.Core;
const Quat = m.linalg.Quat(f32);
const Vec3 = m.linalg.Vec3(f32);
const Vec4 = m.linalg.Vec4(f32);
const Mat4x4 = m.linalg.Mat4x4(f32);

const App = @This();

// fn initScene(self: *App, core: *Core) void {

// // const ico = gltf.load_meshes(core.cpuallocator, "assets/icosphere.glb") catch @panic("Failed to load mesh");
// const numlinesx = 99;
// const numlinesy = 99;
// const totalLines = numlinesx + numlinesy + 1;
// var lines: [totalLines]Vertex = undefined;

// // Calculate the bounds based on the number of *segments*, which is numLines - 1
// const spacing = 1;
// const halfWidth = (numlinesx - 1) * spacing * 0.5;
// const halfDepth = (numlinesy - 1) * spacing * 0.5;
// const color: Vec4 = .new(0.024, 0.024, 0.024, 1.0);
// const xcolor: Vec4 = .new(1.000, 0.162, 0.078, 1.0);
// const ycolor: Vec4 = .new(0.529, 0.949, 0.204, 1.0);
// const zcolor: Vec4 = .new(0.114, 0.584, 0.929, 1.0);
// const rgba8: f32 = @bitCast(color.packU8());
// const xcol: f32 = @bitCast(xcolor.packU8());
// const ycol: f32 = @bitCast(ycolor.packU8());
// const zcol: f32 = @bitCast(zcolor.packU8());

// // Generate lines parallel to the Z-axis (varying X)
// var i: u32 = 0;
// while (i < numlinesx) : (i += 1) {
//     const floati: f32 = @floatFromInt(i); // X coord changes
//     const x = (floati * spacing) - halfDepth;
//     const p0: Vec3 = .new(x, -halfWidth, 0); // Z extent fixed
//     const p1: Vec3 = .new(x, halfWidth, 0); // Z extent fixed
//     const p2: Vec4 = .zeros;
//     // No allocation needed here, append moves the struct
//     if (i == numlinesx / 2) {
//         lines[i] = .new(p0, p1, p2, 0.2, ycol);
//     } else {
//         lines[i] = .new(p0, p1, p2, 0.08, rgba8);
//     }
// }

// // Generate lines parallel to the X-axis (varying Z)
// var j: u32 = 0;
// while (j < numlinesy) : (j += 1) {
//     const floatj: f32 = @floatFromInt(j);
//     const y = (floatj * spacing) - halfWidth; // Z coord changes
//     const p0: Vec3 = .new(-halfDepth, y, 0); // X extent fixed
//     const p1: Vec3 = .new(halfDepth, y, 0); // X extent fixed
//     const p2: Vec4 = .zeros;
//     if (j == numlinesy / 2) {
//         lines[i + j] = .new(p0, p1, p2, 0.2, xcol);
//     } else {
//         lines[i + j] = .new(p0, p1, p2, 0.08, rgba8);
//     }
// }

// const p0: Vec3 = .new(0, 0, -halfDepth); // X extent fixed
// const p1: Vec3 = .new(0, 0, halfDepth); // X extent fixed
// const p2: Vec4 = .zeros;
// lines[i + j] = .new(p0, p1, p2, 0.2, zcol);
// const icoverts = ico.items[0].vertices;
// for (icoverts) |v| {
//     std.debug.print("{}", .{v.position});
// }
// const total_len = icoverts.len + lines.len;
// const total_len = icoverts.len;
// const result = core.cpuallocator.alloc(Vertex, total_len) catch @panic("");
// @memcpy(result[0..lines.len], lines[0..]);
// @memcpy(result[lines.len..], icoverts[0..]);
// defer core.cpuallocator.free(result);
// const indc = ico.items[0].indices;
// core.buffers.vertex = buffer.createSSBO(core, @sizeOf(Vertex) * result.len, true);
// core.buffers.index = buffer.createIndex(core, @sizeOf(u32) * indc.len);
// buffer.upload(core, std.mem.sliceAsBytes(indc), core.buffers.index);
// buffer.upload(core, std.mem.sliceAsBytes(result), core.buffers.vertex);
// const adr = buffer.getDeviceAddress(core, core.buffers.vertex);
// var drawcommands: *c.VkDrawIndexedIndirectCommand = @ptrCast(@alignCast(core.buffers.indirect.info.pMappedData.?));
// drawcommands.firstIndex = 0;
// drawcommands.firstInstance = 0;
// drawcommands.indexCount = 240; //240
// drawcommands.instanceCount = 1;
// drawcommands.vertexOffset = 199;

// for (&core.framecontexts.frames) |*frame| {
// var scene_uniform_data: *buffer.SceneDataUniform = @ptrCast(@alignCast(frame.buffers.scenedata.info.pMappedData.?));
// scene_uniform_data.vertex_buffer_address = adr;
// }
// }

pub fn loop(self: *App, engine: *Core, window: *m.Window) void {
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var delta: u64 = undefined;
    var camerarot: Quat = .identity;
    var camerapos: Vec3 = .{ .x = 0, .y = -5, .z = 8 };
    camerarot.rotatePitch(std.math.degreesToRadians(60));
    camerarot.rotateYaw(std.math.degreesToRadians(180));
    camerarot.rotateRoll(std.math.degreesToRadians(180));

    _ = self;
    // self.initScene(engine);

    while (!window.state.quit) {
        window.processInput();
        if (window.state.w) camerapos.translateForward(&camerarot, 0.1);
        if (window.state.s) camerapos.translateForward(&camerarot, -0.1);
        if (window.state.a) camerapos.translatePitch(&camerarot, -0.1);
        if (window.state.d) camerapos.translatePitch(&camerarot, 0.1);
        if (window.state.q) camerapos.translateWorldZ(-0.1);
        if (window.state.e) camerapos.translateWorldZ(0.1);
        camerarot.rotatePitch(-window.state.mouse_y / 150);
        camerarot.rotateWorldZ(-window.state.mouse_x / 150);
        if (engine.framenumber % 100 == 0) {
            delta = timer.read();
            log.info("FPS: {d}                        \x1b[1A", .{
                @as(u32, (@intFromFloat(100_000_000_000.0 / @as(f32, @floatFromInt(delta))))),
            });
            timer.reset();
        }
        engine.nextFrame(window);
    }
}

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    var window: m.Window = .init(2000, 1200);
    defer window.deinit();
    var engine: Core = .init(allocator, &window);
    defer engine.deinit();
    var app: App = .{};
    // defer app.deinit();
    app.loop(&engine, &window);
}
