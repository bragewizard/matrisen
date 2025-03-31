const std = @import("std");
const meshshadermodule = @import("meshshader.zig");
const pbrmodule = @import("pbr.zig");
const shapesmodule = @import("shapes.zig");
const c = @import("clibs");
const geometry = @import("geometry");
const buffers = @import("../buffers.zig");
const common = @import("common.zig");
const descriptorbuilder = @import("../descriptorbuilder.zig");
const MaterialConstantsUniform = common.MaterialConstantsUniform;
const Writer = descriptorbuilder.Writer;
const Allocator = descriptorbuilder.Allocator;
const Core = @import("../core.zig");
const Vec4 = geometry.Vec4(f32);

meshshader: meshshadermodule = .{},
pbr: pbrmodule = .{},
shapes: shapesmodule = .{},
descriptorallocator: Allocator = .{},

const Self = @This();

pub fn init(core: *Core) void {
    var self = &core.pipelines;
    self.meshshader.init(core);
    self.pbr.init(core);
    self.shapes.init(core);
    common.writeDescriptorsets(self,core);
}

pub fn deinit(core: *Core) void {
    var self = &core.pipelines;
    self.meshshader.deinit(core);
    self.pbr.deinit(core);
    self.shapes.deinit(core);
    self.descriptorallocator.deinit(core.device.handle);
}
