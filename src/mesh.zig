const std = @import("std");
const Vec3 = @import("math/vec3.zig").Vec3;
const Vec2 = @import("math/vec2.zig").Vec2;

pub const Mesh = struct {
    vertices: std.ArrayList(Vec3),
    uvs: std.ArrayList(Vec2),
    normals: std.ArrayList(Vec3),
    indices: usize,

    pub fn fromObjFile(fileName: []const u8, allocator: std.mem.Allocator) !Mesh {
        var vertices = std.ArrayList(Vec3).init(allocator);
        var uvs = std.ArrayList(Vec2).init(allocator);
        var normals = std.ArrayList(Vec3).init(allocator);

        var temp_vert = std.ArrayList(Vec3).init(allocator);
        defer temp_vert.deinit();
        var idx = std.ArrayList(u32).init(allocator);
        defer idx.deinit();

        var temp_uv = std.ArrayList(Vec2).init(allocator);
        defer temp_uv.deinit();
        var uv_indices = std.ArrayList(u32).init(allocator);
        defer uv_indices.deinit();

        var temp_norm = std.ArrayList(Vec3).init(allocator);
        defer temp_norm.deinit();
        var normal_indices = std.ArrayList(u32).init(allocator);
        defer normal_indices.deinit();

        var file = try std.fs.cwd().openFile(fileName, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();

        var buf: [1024]u8 = undefined;
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            var words = std.mem.tokenize(u8, line, " ");

            var elem_type = words.next().?;
            if (std.mem.eql(u8, elem_type, "v")) {
                var x = try std.fmt.parseFloat(f32, words.next().?);
                var y = try std.fmt.parseFloat(f32, words.next().?);
                var z = try std.fmt.parseFloat(f32, words.next().?);

                try temp_vert.append(Vec3{ .x = x, .y = y, .z = z });
            } else if (std.mem.eql(u8, elem_type, "vt")) {
                var u = try std.fmt.parseFloat(f32, words.next().?);
                var v = try std.fmt.parseFloat(f32, words.next().?);

                try temp_uv.append(Vec2{ .x = u, .y = v });
            } else if (std.mem.eql(u8, elem_type, "vn")) {
                var x = try std.fmt.parseFloat(f32, words.next().?);
                var y = try std.fmt.parseFloat(f32, words.next().?);
                var z = try std.fmt.parseFloat(f32, words.next().?);

                try temp_norm.append(Vec3{ .x = x, .y = y, .z = z });
            } else if (std.mem.eql(u8, elem_type, "f")) {
                try parseFaceElement(words.next().?, &idx, &uv_indices, &normal_indices);
                try parseFaceElement(words.next().?, &idx, &uv_indices, &normal_indices);
                try parseFaceElement(words.next().?, &idx, &uv_indices, &normal_indices);
            }
        }

        for (idx.items) |val| {
            try vertices.append(Vec3{ .x = temp_vert.items[val].x, .y = temp_vert.items[val].y, .z = temp_vert.items[val].z });
        }

        for (normal_indices.items) |val| {
            try normals.append(Vec3{ .x = temp_norm.items[val].x, .y = temp_norm.items[val].y, .z = temp_norm.items[val].z });
        }

        for (uv_indices.items) |val| {
            try uvs.append(Vec2{ .x = temp_uv.items[val].x, .y = temp_uv.items[val].y });
        }

        return Mesh{ .indices = idx.items.len, .vertices = vertices, .uvs = uvs, .normals = normals };
    }

    fn parseFaceElement(face: []const u8, idx: *std.ArrayList(u32), uv_idx: *std.ArrayList(u32), normal_idx: *std.ArrayList(u32)) !void {
        var elems = std.mem.split(u8, face, "/");
        var index = try std.fmt.parseInt(u32, elems.next().?, 10);
        try idx.append(index - 1);

        var uv = elems.next().?;

        if (uv.len > 0) {
            var uv_index = try std.fmt.parseInt(u32, uv, 10);
            try uv_idx.append(uv_index - 1);
        }

        if (elems.next()) |norm| {
            var normal_index = try std.fmt.parseInt(u32, norm, 10);
            try normal_idx.append(normal_index - 1);
        }
    }

    pub fn deinit(self: *Mesh) void {
        self.vertices.deinit();
        self.uvs.deinit();
        self.normals.deinit();
    }
};
