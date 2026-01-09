const Vec4 = @import("../math/vec4.zig").Vec4;
const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec2 = @import("../math/vec2.zig").Vec2;

const ClippingPlane = enum(u8) { NEAR, FAR, LEFT, RIGHT, TOP, BOTTOM };

pub const Vertex = struct {
    position: Vec4,
    world_position: Vec3,
    tangent: Vec3,
    bitangent: Vec3,
    normal: Vec3,
    uv: Vec2,

    fn lerp(vertex_a: Vertex, vertex_b: Vertex, t: f32) Vertex {
        return Vertex{
            .position = Vec4.lerp(vertex_a.position, vertex_b.position, t),
            .world_position = Vec3.lerp(vertex_a.world_position, vertex_b.world_position, t),
            .tangent = Vec3.lerp(vertex_a.tangent, vertex_b.tangent, t),
            .bitangent = Vec3.lerp(vertex_a.bitangent, vertex_b.bitangent, t),
            .normal = Vec3.lerp(vertex_a.normal, vertex_b.normal, t),
            .uv = Vec2.lerp(vertex_a.uv, vertex_b.uv, t),
        };
    }

    fn clipToNDC(vertex: Vertex) Vertex {
        const pos = vertex.position;
        const world_pos = vertex.world_position;
        const tangent = vertex.tangent;
        const bitangent = vertex.bitangent;
        const nor = vertex.normal;
        const uv = vertex.uv;
        const one_over_w = 1.0 / pos.w;
        return Vertex{
            .position = Vec4{ .x = pos.x / pos.w, .y = pos.y / pos.w, .z = pos.z / pos.w, .w = pos.w },
            .world_position = Vec3{ .x = world_pos.x * one_over_w, .y = world_pos.y * one_over_w, .z = world_pos.z * one_over_w },
            .tangent = Vec3{ .x = tangent.x * one_over_w, .y = tangent.y * one_over_w, .z = tangent.z * one_over_w },
            .bitangent = Vec3{ .x = bitangent.x * one_over_w, .y = bitangent.y * one_over_w, .z = bitangent.z * one_over_w },
            .normal = Vec3{ .x = nor.x * one_over_w, .y = nor.y * one_over_w, .z = nor.z * one_over_w },
            .uv = Vec2{ .x = uv.x * one_over_w, .y = uv.y * one_over_w },
        };
    }
};

pub const Tri = struct {
    v0: Vertex,
    v1: Vertex,
    v2: Vertex,
    material_idx: u32 = 0,

    pub fn clipToNDC(tri: Tri) Tri {
        return Tri{
            .v0 = Vertex.clipToNDC(tri.v0),
            .v1 = Vertex.clipToNDC(tri.v1),
            .v2 = Vertex.clipToNDC(tri.v2),
        };
    }

    pub fn clipAgainstFrustrum(tri_in: Tri, tri_out: *[8]Tri) u8 {
        var polygon_in: Polygon = Polygon{ .count = 3, .vertices = .{ tri_in.v0, tri_in.v1, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2 } };

        const vertex_count = clipPolygonAgainstAllPlane(&polygon_in);
        if (vertex_count < 3) return 0;

        const tri_count = vertex_count - 2;
        for (0..tri_count) |i| {
            tri_out[i].v0 = polygon_in.vertices[0];
            tri_out[i].v1 = polygon_in.vertices[i + 1];
            tri_out[i].v2 = polygon_in.vertices[i + 2];
        }
        return tri_count;
    }
};

const Polygon = struct { vertices: [10]Vertex, count: u8 };

fn insidePlane(vertex_in: Vertex, plane: ClippingPlane) bool {
    const vertex = vertex_in.position;
    switch (plane) {
        .NEAR => return vertex.z >= -vertex.w,
        .FAR => return vertex.z <= vertex.w,
        .LEFT => return vertex.x >= -vertex.w,
        .RIGHT => return vertex.x <= vertex.w,
        .TOP => return vertex.y <= vertex.w,
        .BOTTOM => return vertex.y >= -vertex.w,
    }
}

fn intersectPlane(vertex0: Vertex, vertex1: Vertex, plane: ClippingPlane) f32 {
    const v0 = vertex0.position;
    const v1 = vertex1.position;
    var t: f32 = 0.0;
    switch (plane) {
        .NEAR => t = (-v0.w - v0.z) / ((v1.z - v0.z) + (v1.w - v0.w)),
        .FAR => t = (v0.w - v0.z) / ((v1.z - v0.z) - (v1.w - v0.w)),
        .LEFT => t = (-v0.w - v0.x) / ((v1.x - v0.x) + (v1.w - v0.w)),
        .RIGHT => t = (v0.w - v0.x) / ((v1.x - v0.x) - (v1.w - v0.w)),
        .TOP => t = (v0.w - v0.y) / ((v1.y - v0.y) - (v1.w - v0.w)),
        .BOTTOM => t = (-v0.w - v0.y) / ((v1.y - v0.y) + (v1.w - v0.w)),
    }
    return t;
}

fn clipPolygonAgainstPlane(polygon_in: *Polygon, polygon_out: *Polygon, plane: ClippingPlane) void {
    if (polygon_in.count == 0) return;

    polygon_out.count = 0;

    var prev: Vertex = polygon_in.vertices[polygon_in.count - 1];
    var prev_inside: bool = insidePlane(prev, plane);

    for (0..polygon_in.count) |i| {
        const curr: Vertex = polygon_in.vertices[i];
        const curr_inside: bool = insidePlane(curr, plane);

        if (curr_inside) {
            if (!prev_inside) {
                const t = intersectPlane(prev, curr, plane);
                polygon_out.vertices[polygon_out.count] = Vertex.lerp(prev, curr, t);
                polygon_out.count += 1;
            }
            polygon_out.vertices[polygon_out.count] = curr;
            polygon_out.count += 1;
        } else if (prev_inside) {
            const t = intersectPlane(prev, curr, plane);
            polygon_out.vertices[polygon_out.count] = Vertex.lerp(prev, curr, t);
            polygon_out.count += 1;
        }

        prev = curr;
        prev_inside = curr_inside;
    }
}

fn clipPolygonAgainstAllPlane(polygon_in: *Polygon) u8 {
    var temp1: Polygon = undefined;
    var temp2: Polygon = undefined;

    var input: *Polygon = polygon_in;
    var output: *Polygon = &temp1;

    for (0..6) |i| {
        const e: ClippingPlane = @enumFromInt(i);
        clipPolygonAgainstPlane(input, output, e);

        if (output.count == 0) {
            polygon_in.count = 0;
            return 0;
        }
        if (output == &temp1) {
            input = &temp1;
            output = &temp2;
        } else {
            input = &temp2;
            output = &temp1;
        }
    }

    @memcpy(polygon_in.vertices[0..], input.*.vertices[0..]);
    polygon_in.count = input.*.count;
    return polygon_in.count;
}

pub fn calculateTangent(pos1: Vec3, pos2: Vec3, pos3: Vec3, uv1: Vec2, uv2: Vec2, uv3: Vec2) Vec3 {
    const edge1: Vec3 = Vec3.sub(pos2, pos1);
    const edge2: Vec3 = Vec3.sub(pos3, pos1);
    const deltaUV1: Vec2 = Vec2.sub(uv2, uv1);
    const deltaUV2: Vec2 = Vec2.sub(uv3, uv1);

    const f: f32 = 1.0 / (deltaUV1.x * deltaUV2.y - deltaUV2.x * deltaUV1.y);

    var tangent: Vec3 = Vec3.init(0.0);
    tangent.x = f * (deltaUV2.y * edge1.x - deltaUV1.y * edge2.x);
    tangent.y = f * (deltaUV2.y * edge1.y - deltaUV1.y * edge2.y);
    tangent.z = f * (deltaUV2.y * edge1.z - deltaUV1.y * edge2.z);
    return tangent;
}
