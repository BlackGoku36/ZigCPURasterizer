const std = @import("std");
const Vec3 = @import("vec3.zig").Vec3;
const Vec2 = @import("vec2.zig").Vec2;

pub const Mesh = struct {
    vertices: std.ArrayList(Vec3),
    indices: std.ArrayList(u32),
    uvs: std.ArrayList(Vec2),
    uv_indices: std.ArrayList(u32),
    normals: std.ArrayList(Vec3),
    normal_indices: std.ArrayList(u32),

    pub fn fromObjFile(fileName: []const u8, allocator: std.mem.Allocator) !Mesh {
        var vert = std.ArrayList(Vec3).init(allocator);
        var idx = std.ArrayList(u32).init(allocator);
        var uvs = std.ArrayList(Vec2).init(allocator);
        var uv_indices = std.ArrayList(u32).init(allocator);
        var norm = std.ArrayList(Vec3).init(allocator);
        var normal_indices = std.ArrayList(u32).init(allocator);

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

                try vert.append(Vec3{ .x = x, .y = y, .z = z });
            } else if (std.mem.eql(u8, elem_type, "vt")) {
                var u = try std.fmt.parseFloat(f32, words.next().?);
                var v = try std.fmt.parseFloat(f32, words.next().?);

                try uvs.append(Vec2{ .x = u, .y = v });
            } else if (std.mem.eql(u8, elem_type, "vn")) {
                var x = try std.fmt.parseFloat(f32, words.next().?);
                var y = try std.fmt.parseFloat(f32, words.next().?);
                var z = try std.fmt.parseFloat(f32, words.next().?);

                try norm.append(Vec3{ .x = x, .y = y, .z = z });
            } else if (std.mem.eql(u8, elem_type, "f")) {
                try parseFaceElement(words.next().?, &idx, &uv_indices, &normal_indices);
                try parseFaceElement(words.next().?, &idx, &uv_indices, &normal_indices);
                try parseFaceElement(words.next().?, &idx, &uv_indices, &normal_indices);
            }
        }

        return Mesh{ .vertices = vert, .indices = idx, .uvs = uvs, .uv_indices = uv_indices, .normals = norm, .normal_indices = normal_indices };
    }

    fn parseFaceElement(face: []const u8, idx: *std.ArrayList(u32), uv_idx: *std.ArrayList(u32), normal_idx: *std.ArrayList(u32)) !void {
        var elems = std.mem.tokenize(u8, face, "/");
        var index = try std.fmt.parseInt(u32, elems.next().?, 10);
        try idx.append(index);

        if (elems.next()) |uv| {
            var uv_index = try std.fmt.parseInt(u32, uv, 10);
            try uv_idx.append(uv_index);
        }

        if (elems.next()) |norm| {
            var normal_index = try std.fmt.parseInt(u32, norm, 10);
            try normal_idx.append(normal_index);
        }
    }

    pub fn destroy(self: *Mesh) void {
        self.vertices.deinit();
        self.indices.deinit();
        self.uvs.deinit();
        self.normals.deinit();
    }
};
