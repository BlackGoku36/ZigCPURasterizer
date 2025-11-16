const std = @import("std");
const Vec3 = @import("math/vec3.zig").Vec3;
const Vec2 = @import("math/vec2.zig").Vec2;

pub const Mesh = struct {
    vertices: std.ArrayList(Vec3),
    uvs: std.ArrayList(Vec2),
    normals: std.ArrayList(Vec3),
    indices: usize,

    pub fn fromObjFile(fileName: []const u8, allocator: std.mem.Allocator) !Mesh {
        var vertices: std.ArrayList(Vec3) = .{};
        var uvs: std.ArrayList(Vec2) = .{};
        var normals: std.ArrayList(Vec3) = .{};

        var temp_vert: std.ArrayList(Vec3) = .{};
        defer temp_vert.deinit(allocator);
        var idx: std.ArrayList(u32) = .{};
        defer idx.deinit(allocator);

        var temp_uv: std.ArrayList(Vec2) = .{};
        defer temp_uv.deinit(allocator);
        var uv_indices: std.ArrayList(u32) = .{};
        defer uv_indices.deinit(allocator);

        var temp_norm: std.ArrayList(Vec3) = .{};
        defer temp_norm.deinit(allocator);
        var normal_indices: std.ArrayList(u32) = .{};
        defer normal_indices.deinit(allocator);

        var file: std.fs.File = undefined;

        if (std.fs.cwd().openFile(fileName, .{})) |f| {
            file = f;
        } else |err| {
            std.debug.print("File not found: {any}\n", .{err});
        }
        defer file.close();

        var stdin_buffer: [512]u8 = undefined;
        var stdin_reader_wrapper = file.reader(&stdin_buffer);
        const in_stream: *std.Io.Reader = &stdin_reader_wrapper.interface;
        // in_stream.delimite

        // var buf_reader = std.io.bufferedReader(file.reader());
        // var in_stream = file.reader();

        // var buf: [1024]u8 = undefined;
        while (in_stream.takeDelimiterExclusive('\n')) |line| {
            // var words = std.mem.tokenize(u8, std.mem.trim(u8, line, "\r"), " ");
            var words = std.mem.tokenizeScalar(u8, std.mem.trim(u8, line, "\r"), ' ');

            if (words.next()) |elem_type| {
                if (std.mem.eql(u8, elem_type, "v")) {
                    const x = try std.fmt.parseFloat(f32, words.next().?);
                    const y = try std.fmt.parseFloat(f32, words.next().?);
                    const z = try std.fmt.parseFloat(f32, words.next().?);

                    try temp_vert.append(allocator, Vec3{ .x = x, .y = y, .z = z });
                } else if (std.mem.eql(u8, elem_type, "vt")) {
                    const u = try std.fmt.parseFloat(f32, words.next().?);
                    const v = try std.fmt.parseFloat(f32, words.next().?);

                    try temp_uv.append(allocator, Vec2{ .x = u, .y = v });
                } else if (std.mem.eql(u8, elem_type, "vn")) {
                    const x = try std.fmt.parseFloat(f32, words.next().?);
                    const y = try std.fmt.parseFloat(f32, words.next().?);
                    const z = try std.fmt.parseFloat(f32, words.next().?);

                    try temp_norm.append(allocator, Vec3{ .x = x, .y = y, .z = z });
                } else if (std.mem.eql(u8, elem_type, "f")) {
                    try parseFaceElement(allocator, words.next().?, &idx, &uv_indices, &normal_indices);
                    try parseFaceElement(allocator, words.next().?, &idx, &uv_indices, &normal_indices);
                    try parseFaceElement(allocator, words.next().?, &idx, &uv_indices, &normal_indices);
                }
            }
        } else |err| switch (err) {
       	error.EndOfStream => {
                    // reached end
                    // the normal case
                },
                error.StreamTooLong => {
                    // the line was longer than the internal buffer
                    return err;
                },
                error.ReadFailed => {
                    // the read failed
                    return err;
                },
        }

        for (idx.items) |val| {
            try vertices.append(allocator, Vec3{ .x = temp_vert.items[val].x, .y = temp_vert.items[val].y, .z = temp_vert.items[val].z });
        }

        for (normal_indices.items) |val| {
            try normals.append(allocator, Vec3{ .x = temp_norm.items[val].x, .y = temp_norm.items[val].y, .z = temp_norm.items[val].z });
        }

        for (uv_indices.items) |val| {
            try uvs.append(allocator, Vec2{ .x = temp_uv.items[val].x, .y = temp_uv.items[val].y });
        }

        return Mesh{ .indices = idx.items.len, .vertices = vertices, .uvs = uvs, .normals = normals };
    }

    fn parseFaceElement(allocator: std.mem.Allocator, face: []const u8, idx: *std.ArrayList(u32), uv_idx: *std.ArrayList(u32), normal_idx: *std.ArrayList(u32)) !void {
        // var elems = std.mem.split(u8, face, "/");
        var elems = std.mem.splitScalar(u8, face, '/');
        const index = try std.fmt.parseInt(u32, elems.next().?, 10);
        try idx.append(allocator,index - 1);

        const uv = elems.next().?;

        if (uv.len > 0) {
            const uv_index = try std.fmt.parseInt(u32, uv, 10);
            try uv_idx.append(allocator, uv_index - 1);
        }

        if (elems.next()) |norm| {
            const normal_index = try std.fmt.parseInt(u32, norm, 10);
            try normal_idx.append(allocator, normal_index - 1);
        }
    }

    pub fn deinit(self: *Mesh, allocator: std.mem.Allocator) void {
        self.vertices.deinit(allocator);
        self.uvs.deinit(allocator);
        self.normals.deinit(allocator);
    }
};
