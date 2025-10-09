const std = @import("std");
const m = @import("matrisen");
const log = std.log.scoped(.app);
const c = m.clibs;
const buffer = m.buffer;
const SceneDataUniform = m.DefaultPipeline.SceneDataUniform;
const Core = m.Core;
const FrameContext = m.command.FrameContext;
const AllocatedBuffer = m.buffer.AllocatedBuffer;
const Vertex = m.buffer.Vertex;
const Allocator = m.descriptor.Allocator;
const Writer = m.descriptor.Writer;
const Quat = m.linalg.Quat(f32);
const Vec3 = m.linalg.Vec3(f32);
const Vec4 = m.linalg.Vec4(f32);
const Mat4x4 = m.linalg.Mat4x4(f32);

const multibuffering = m.Core.multibuffering;

const App = @This();

const DynamicData = struct {
    descriptors: Allocator = .{},
    poses: AllocatedBuffer = undefined,
    scenedata: AllocatedBuffer = undefined,
};

const StaticData = struct {
    indirect: AllocatedBuffer = undefined,
    vertex: AllocatedBuffer = undefined,
    index: AllocatedBuffer = undefined, //FIX figure out what to do about indexbuffers as they need to be bound
    resourcetable: AllocatedBuffer = undefined,
};

data: [multibuffering]DynamicData = @splat(.{}),
sdata: StaticData = .{},

// pub fn destroyBuffers(self: *FrameContext, core: *Core) void {
//     c.vmaDestroyBuffer(core.gpuallocator, self.buffers.scenedata.buffer, self.buffers.scenedata.allocation);
//     c.vmaDestroyBuffer(core.gpuallocator, self.buffers.poses.buffer, self.buffers.poses.allocation);
// }

// pub fn uploadSceneData(self: *App, core: *Core, view: Mat4x4) void {
//     const current = core.framecontexts.current;
//     var frame = &core.framecontexts.frames[current];
//     var scene_uniform_data: *SceneDataUniform = @ptrCast(@alignCast(self.data[current].scenedata.info.pMappedData.?));
//     scene_uniform_data.view = view;
//     scene_uniform_data.proj = Mat4x4.perspective(
//         std.math.degreesToRadians(60.0),
//         @as(f32, @floatFromInt(frame.draw_extent.width)) / @as(f32, @floatFromInt(frame.draw_extent.height)),
//         0.1,
//         1000.0,
//     );
//     scene_uniform_data.viewproj = Mat4x4.mul(scene_uniform_data.proj, scene_uniform_data.view);
//     scene_uniform_data.sunlight_dir = .{ .x = 0.1, .y = 0.1, .z = 1, .w = 1 };
//     scene_uniform_data.sunlight_color = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
//     scene_uniform_data.ambient_color = .{ .x = 1, .y = 0.6, .z = 0, .w = 1 };

//     var poses: *[2]Mat4x4 = @ptrCast(@alignCast(self.data[current].poses.info.pMappedData.?));

//     var time: f32 = @floatFromInt(core.framenumber);
//     time /= 100;
//     var mod = Mat4x4.rotation(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, time / 2.0);
//     mod = mod.rotate(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, time);
//     mod = mod.translate(.{ .x = 2.0, .y = 2.0, .z = 2.0 });
//     poses[0] = Mat4x4.identity;
//     poses[1] = mod;
// }

// FIX this is temporary, need to move code where it is appropriate
pub fn initScene(self: *App, core: *Core) void {
    var sizes = [_]Allocator.PoolSizeRatio{
        .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
        .{ .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 1 },
    };
    core.globaldescriptorallocator.init(core.device.handle, 10, &sizes, core.cpuallocator);

    var ratios = [_]Allocator.PoolSizeRatio{
        .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE },
        .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER },
        .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER },
        .{ .ratio = 4, .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER },
    };

    core.pipelinestatic_set = core.globaldescriptorallocator.allocate(
        core.cpuallocator,
        core.device.handle,
        self.resourcelayout,
        null,
    );

    for (0.., &self.dynamicdescriptorallocators) |i, *element| {
        element.init(core.device.handle, 1000, &ratios, core.cpuallocator);
        self.dynamic_sets[i] = element.allocate(
            core.cpuallocator,
            core.device.handle,
            self.scenedatalayout,
            null,
        );
    }
    core.buffers.indirect = m.buffer.createIndirect(core, 1);

    // FIX this is hardcoded two objects for the time beeing
    const resourses1: m.buffer.ResourceEntry = .{ .pose = 0, .object = 0, .vertex_offset = 0 };
    const resourses2: m.buffer.ResourceEntry = .{ .pose = 1, .object = 1, .vertex_offset = 199 };
    const resources: [2]m.buffer.ResourceEntry = .{ resourses1, resourses2 };
    const resources_slice = std.mem.sliceAsBytes(&resources);

    self.sdata.resourcetable = m.buffer.createSSBO(core, resources_slice.len, true);
    m.buffer.upload(core, resources_slice, core.buffers.resourcetable);

    for (&self.data) |*data| {
        data.scenedata = buffer.create(
            core,
            @sizeOf(SceneDataUniform),
            m.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            m.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );

        data.poses = buffer.create(
            core,
            @sizeOf(Mat4x4) * 2,
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
    }

    var pipeline = &core.pipelines.vertexshader;
    pipeline.writeSetSBBO(&core, self.sdata.resourcetable, buffer.ResourceEntry);
    for (0.., &self.data) |i, *data| {
        const adr = buffer.getDeviceAddress(core, self.data[i].poses);
        var scene_uniform_data: *SceneDataUniform = @ptrCast(@alignCast(data.scenedata.info.pMappedData.?));
        scene_uniform_data.pose_buffer_address = adr;
        {
            var writer = Writer.init();
            defer writer.deinit(core.cpuallocator);
            writer.writeBuffer(
                core.cpuallocator,
                0,
                data.scenedata.buffer,
                @sizeOf(SceneDataUniform),
                0,
                c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            );
            writer.updateSet(core.device.handle, pipeline.dynamic_sets[i]);
        }
    }
    // const ico = gltf.load_meshes(core.cpuallocator, "assets/icosphere.glb") catch @panic("Failed to load mesh");
    const numlinesx = 99;
    const numlinesy = 99;
    const totalLines = numlinesx + numlinesy + 1;
    var lines: [totalLines]Vertex = undefined;

    // Calculate the bounds based on the number of *segments*, which is numLines - 1
    const spacing = 1;
    const halfWidth = (numlinesx - 1) * spacing * 0.5;
    const halfDepth = (numlinesy - 1) * spacing * 0.5;
    const color: Vec4 = .new(0.024, 0.024, 0.024, 1.0);
    const xcolor: Vec4 = .new(1.000, 0.162, 0.078, 1.0);
    const ycolor: Vec4 = .new(0.529, 0.949, 0.204, 1.0);
    const zcolor: Vec4 = .new(0.114, 0.584, 0.929, 1.0);
    const rgba8: f32 = @bitCast(color.packU8());
    const xcol: f32 = @bitCast(xcolor.packU8());
    const ycol: f32 = @bitCast(ycolor.packU8());
    const zcol: f32 = @bitCast(zcolor.packU8());

    // Generate lines parallel to the Z-axis (varying X)
    var i: u32 = 0;
    while (i < numlinesx) : (i += 1) {
        const floati: f32 = @floatFromInt(i); // X coord changes
        const x = (floati * spacing) - halfDepth;
        const p0: Vec3 = .new(x, -halfWidth, 0); // Z extent fixed
        const p1: Vec3 = .new(x, halfWidth, 0); // Z extent fixed
        const p2: Vec4 = .zeros;
        // No allocation needed here, append moves the struct
        if (i == numlinesx / 2) {
            lines[i] = .new(p0, p1, p2, 0.2, ycol);
        } else {
            lines[i] = .new(p0, p1, p2, 0.08, rgba8);
        }
    }

    // Generate lines parallel to the X-axis (varying Z)
    var j: u32 = 0;
    while (j < numlinesy) : (j += 1) {
        const floatj: f32 = @floatFromInt(j);
        const y = (floatj * spacing) - halfWidth; // Z coord changes
        const p0: Vec3 = .new(-halfDepth, y, 0); // X extent fixed
        const p1: Vec3 = .new(halfDepth, y, 0); // X extent fixed
        const p2: Vec4 = .zeros;
        if (j == numlinesy / 2) {
            lines[i + j] = .new(p0, p1, p2, 0.2, xcol);
        } else {
            lines[i + j] = .new(p0, p1, p2, 0.08, rgba8);
        }
    }

    const p0: Vec3 = .new(0, 0, -halfDepth); // X extent fixed
    const p1: Vec3 = .new(0, 0, halfDepth); // X extent fixed
    const p2: Vec4 = .zeros;
    lines[i + j] = .new(p0, p1, p2, 0.2, zcol);
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
}

pub fn loop(self: *App, engine: *Core, window: *m.Window) void {
    // var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    // var delta: u64 = undefined;
    _ = engine;
    // var camerarot: Quat = .identity;
    // var camerapos: Vec3 = .{ .x = 0, .y = -5, .z = 8 };
    // camerarot.rotatePitch(std.math.degreesToRadians(60));
    // camerarot.rotateYaw(std.math.degreesToRadians(180));
    // camerarot.rotateRoll(std.math.degreesToRadians(180));

    m.Window.check_sdl_bool(m.SDL_SetWindowRelativeMouseMode(window.sdl_window, true));
    window.state.capture_mouse = true;
    _ = self;
    // self.initScene(engine);

    while (!window.state.quit) {
        window.processInput();
        // if (window.state.w) camerapos.translateForward(&camerarot, 0.1);
        // if (window.state.s) camerapos.translateForward(&camerarot, -0.1);
        // if (window.state.a) camerapos.translatePitch(&camerarot, -0.1);
        // if (window.state.d) camerapos.translatePitch(&camerarot, 0.1);
        // if (window.state.q) camerapos.translateWorldZ(-0.1);
        // if (window.state.e) camerapos.translateWorldZ(0.1);
        // camerarot.rotatePitch(-window.state.mouse_y / 150);
        // camerarot.rotateWorldZ(-window.state.mouse_x / 150);
        // if (engine.framenumber % 100 == 0) {
        //     delta = timer.read();
        //     log.info("FPS: {d}                        \x1b[1A", .{
        //         @as(u32, (@intFromFloat(100_000_000_000.0 / @as(f32, @floatFromInt(delta))))),
        //     });
        //     timer.reset();
        // }
        // if (engine.resizerequest) {
        //     window.get_size(&engine.images.swapchain_extent.width, &engine.images.swapchain_extent.height);
        //     m.Swapchain.resize(engine);
        //     continue;
        // }
        // var frame = &engine.framecontexts.frames[engine.framecontexts.current];
        // frame.submitBegin(engine) catch continue;
        // // self.uploadSceneData(engine, camerarot.view(camerapos));
        // // engine.pipelines.vertexshader.draw(engine, frame);
        // frame.submitEnd(engine);
    }
}

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    var window: m.Window = .init(2000, 1200);
    defer window.deinit();
    var engine: Core = .init(allocator, &window);
    defer engine.deinit();
    // var app: App = .{};
    // defer app.deinit();
    // app.loop(&engine, &window);
}
