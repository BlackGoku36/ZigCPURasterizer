const std = @import("std");
const zigimg = @import("zigimg");
const obj = @import("zig-obj");

const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec4 = @import("../math/vec4.zig").Vec4;
const Vec2 = @import("../math/vec2.zig").Vec2;
const Matrix4 = @import("../math/matrix4.zig").Matrix4;
const Quat = @import("../math/quaternion.zig").Quat;

const rendertarget = @import("rendertarget.zig");
const RenderTargetRGBA16 = rendertarget.RenderTargetRGBA16;
const RenderTargetR16 = rendertarget.RenderTargetR16;
const Color = rendertarget.Color;

const TextureR = @import("../utils/texture.zig").TextureR;
const TextureRGB = @import("../utils/texture.zig").TextureRGB;
const TexturePBR = @import("../utils/texture.zig").TexturePBR;
const PBRSolid = @import("../utils/texture.zig").PBRSolid;
const RGB = @import("../utils/texture.zig").RGB;
const PBR = @import("../utils/texture.zig").PBR;
const PBRTextureDescriptor = @import("../utils/texture.zig").PBRTextureDescriptor;

const material_import = @import("../material.zig");
const Materials = material_import.Materials;
const Material = material_import.Material;

const Mesh = @import("../mesh.zig").Mesh;
const Scene = @import("../mesh.zig").Scene;

const ltc = @import("ltc_lut.zig");
const LTC1 = ltc.LTC1Vec;
const LTC2 = ltc.LTC2Vec;

// pub const width = 1280;
// pub const height = 720;
pub const width = 1500;
pub const height = 750;

const WindingOrder = enum { CW, CCW };
const ClippingPlane = enum(u8) { NEAR, FAR, LEFT, RIGHT, TOP, BOTTOM };
const Vertex = struct {
    position: Vec4,
    world_position: Vec3,
    tangent: Vec3,
    bitangent: Vec3,
    normal: Vec3,
    uv: Vec2,
};
const Tri = struct {
    v0: Vertex,
    v1: Vertex,
    v2: Vertex,
};
const Polygon = struct { vertices: [10]Vertex, count: u8 };
fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn lerpVec2(a: Vec2, b: Vec2, t: f32) Vec2 {
    return Vec2{
        .x = lerp(a.x, b.x, t),
        .y = lerp(a.y, b.y, t),
    };
}

fn lerpVec3(a: Vec3, b: Vec3, t: f32) Vec3 {
    return Vec3{
        .x = lerp(a.x, b.x, t),
        .y = lerp(a.y, b.y, t),
        .z = lerp(a.z, b.z, t),
    };
}

fn lerpVec4(a: Vec4, b: Vec4, t: f32) Vec4 {
    return Vec4{
        .x = lerp(a.x, b.x, t),
        .y = lerp(a.y, b.y, t),
        .z = lerp(a.z, b.z, t),
        .w = lerp(a.w, b.w, t),
    };
}

fn lerpVertex(vertex_a: Vertex, vertex_b: Vertex, t: f32) Vertex {
    return Vertex{
        .position = lerpVec4(vertex_a.position, vertex_b.position, t),
        .world_position = lerpVec3(vertex_a.world_position, vertex_b.world_position, t),
        .tangent = lerpVec3(vertex_a.tangent, vertex_b.tangent, t),
        .bitangent = lerpVec3(vertex_a.bitangent, vertex_b.bitangent, t),
        .normal = lerpVec3(vertex_a.normal, vertex_b.normal, t),
        .uv = lerpVec2(vertex_a.uv, vertex_b.uv, t),
    };
}

// TODO: Learn how this intersect code work
fn get_intersect_t(start: Vec4, end: Vec4) f32 {
    // const d_start = start.z + start.w;
    // const d_end = end.z + end.w;

    // t = dist_start / (dist_start - dist_end)
    // We assume d_start and d_end have different signs (one in, one out)
    // return d_start / (d_start - d_end);
    const dz = end.z - start.z;
    const dw = end.w - start.w;
    return -(start.z + start.w) / (dz + dw);
}

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
                polygon_out.vertices[polygon_out.count] = lerpVertex(prev, curr, t);
                polygon_out.count += 1;
            }
            polygon_out.vertices[polygon_out.count] = curr;
            polygon_out.count += 1;
        } else if (prev_inside) {
            const t = intersectPlane(prev, curr, plane);
            polygon_out.vertices[polygon_out.count] = lerpVertex(prev, curr, t);
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

fn clipTriangle(tri_in: Tri, tri_out: *[8]Tri) u8 {
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

const AABB = struct {
    min_x: u32,
    max_x: u32,
    min_y: u32,
    max_y: u32,

    fn getFrom(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) ?AABB {
        var min_x = @min(ax, bx, cx);
        var min_y = @min(ay, by, cy);
        // min_x = @max(min_x, 0.0);
        // min_y = @max(min_y, 0.0);

        var max_x = @max(ax, bx, cx);
        var max_y = @max(ay, by, cy);
        // max_x = @min(max_x, width);
        // max_y = @min(max_y, height);

        if (min_x > width - 1 or max_x < 0 or min_y > height - 1 or max_y < 0) {
            return null;
        } else {
            min_x = @max(0.0, min_x);
            max_x = @min(width - 1, max_x);
            min_y = @max(0.0, min_y);
            max_y = @min(height - 1, max_y);

            return AABB{ .min_x = @intFromFloat(min_x), .min_y = @intFromFloat(min_y), .max_x = @intFromFloat(max_x), .max_y = @intFromFloat(max_y) };
        }
    }
};

fn edgeFunction(a: Vec3, b: Vec3, px: f32, py: f32) f32 {
    return (px - a.x) * (b.y - a.y) - (py - a.y) * (b.x - a.x);
}

fn windingOrderTest(order: WindingOrder, w0: f32, w1: f32, w2: f32) bool {
    if (order == WindingOrder.CCW) {
        return (w0 >= 0 and w1 >= 0 and w2 >= 0);
    } else {
        return (w0 < 0 and w1 < 0 and w2 < 0);
    }
}

fn vertexClipToNDC(vertex: Vertex) Vertex {
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

fn triClipToNDC(tri: Tri) Tri {
    return Tri{
        .v0 = vertexClipToNDC(tri.v0),
        .v1 = vertexClipToNDC(tri.v1),
        .v2 = vertexClipToNDC(tri.v2),
    };
}

fn fresnelSchlick(f0: Vec3, cosTheta: f32) Vec3 {
    // F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
    // return F0 + (1.0 - F0)*pow((1.0 + 0.000001/*avoid negative approximation when cosTheta = 1*/) - cosTheta, 5.0);
    const c = std.math.pow(f32, 1.0 + 0.000001 - cosTheta, 5.0);
    return Vec3{
        .x = f0.x + (1.0 - f0.x) * c,
        .y = f0.y + (1.0 - f0.y) * c,
        .z = f0.z + (1.0 - f0.z) * c,
    };
}

fn normalDistributionGGX(normal: Vec3, half_vec: Vec3, roughness: f32) f32 {
    const a: f32 = roughness * roughness;
    const a2: f32 = a * a;
    const ndotH: f32 = @max(Vec3.dot(normal, half_vec), 0.0);
    const ndotH2: f32 = ndotH * ndotH;

    const num: f32 = a2;
    var denom: f32 = (ndotH2 * (a2 - 1.0) + 1.0);
    denom = std.math.pi * denom * denom;

    return num / denom;
}

fn geometrySchlickGGX(ndotV: f32, roughness: f32) f32 {
    const r: f32 = (roughness + 1.0);
    const k: f32 = (r * r) / 8.0;

    const num: f32 = ndotV;
    const denom: f32 = ndotV * (1.0 - k) + k;

    return num / denom;
}

fn geometrySmith(normal: Vec3, view_dir: Vec3, light_dir: Vec3, roughness: f32) f32 {
    const ndotV: f32 = @max(Vec3.dot(normal, view_dir), 0.0);
    const ndotL: f32 = @max(Vec3.dot(normal, light_dir), 0.0);
    const ggx2: f32 = geometrySchlickGGX(ndotV, roughness);
    const ggx1: f32 = geometrySchlickGGX(ndotL, roughness);

    return ggx1 * ggx2;
}

fn calculateTangent(pos1: Vec3, pos2: Vec3, pos3: Vec3, uv1: Vec2, uv2: Vec2, uv3: Vec2) Vec3 {
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

fn clipOp(a: Vec3, b: Vec3) Vec3 {
    const term1 = Vec3.multf(b, -a.z);
    const term2 = Vec3.multf(a, b.z);
    return Vec3.add(term1, term2);
}

// Source: https://blog.selfshadow.com/sandbox/ltc.html
pub fn clipQuadToHorizon(L: *[5]Vec3, n: *usize) void {
    // Detect clipping config
    var config: u32 = 0;
    if (L[0].z > 0.0) config += 1;
    if (L[1].z > 0.0) config += 2;
    if (L[2].z > 0.0) config += 4;
    if (L[3].z > 0.0) config += 8;

    // Clip
    n.* = 0;

    if (config == 0) {
        // clip all
    } else if (config == 1) { // V1 clip V2 V3 V4
        n.* = 3;
        L[1] = clipOp(L[1], L[0]);
        L[2] = clipOp(L[3], L[0]);
    } else if (config == 2) { // V2 clip V1 V3 V4
        n.* = 3;
        L[0] = clipOp(L[0], L[1]);
        L[2] = clipOp(L[2], L[1]);
    } else if (config == 3) { // V1 V2 clip V3 V4
        n.* = 4;
        L[2] = clipOp(L[2], L[1]);
        L[3] = clipOp(L[3], L[0]);
    } else if (config == 4) { // V3 clip V1 V2 V4
        n.* = 3;
        L[0] = clipOp(L[3], L[2]);
        L[1] = clipOp(L[1], L[2]);
    } else if (config == 5) { // V1 V3 clip V2 V4 (impossible)
        n.* = 0;
    } else if (config == 6) { // V2 V3 clip V1 V4
        n.* = 4;
        L[0] = clipOp(L[0], L[1]);
        L[3] = clipOp(L[3], L[2]);
    } else if (config == 7) { // V1 V2 V3 clip V4
        n.* = 5;
        L[4] = clipOp(L[3], L[0]);
        L[3] = clipOp(L[3], L[2]);
    } else if (config == 8) { // V4 clip V1 V2 V3
        n.* = 3;
        L[0] = clipOp(L[0], L[3]);
        L[1] = clipOp(L[2], L[3]);
        L[2] = L[3]; // Direct assignment
    } else if (config == 9) { // V1 V4 clip V2 V3
        n.* = 4;
        L[1] = clipOp(L[1], L[0]);
        L[2] = clipOp(L[2], L[3]);
    } else if (config == 10) { // V2 V4 clip V1 V3 (impossible)
        n.* = 0;
    } else if (config == 11) { // V1 V2 V4 clip V3
        n.* = 5;
        L[4] = L[3]; // Direct assignment
        L[3] = clipOp(L[2], L[3]);
        L[2] = clipOp(L[2], L[1]);
    } else if (config == 12) { // V3 V4 clip V1 V2
        n.* = 4;
        L[1] = clipOp(L[1], L[2]);
        L[0] = clipOp(L[0], L[3]);
    } else if (config == 13) { // V1 V3 V4 clip V2
        n.* = 5;
        L[4] = L[3]; // Direct assignment
        L[3] = L[2]; // Direct assignment
        L[2] = clipOp(L[1], L[2]);
        L[1] = clipOp(L[1], L[0]);
    } else if (config == 14) { // V2 V3 V4 clip V1
        n.* = 5;
        L[4] = clipOp(L[0], L[3]);
        L[0] = clipOp(L[0], L[1]);
    } else if (config == 15) { // V1 V2 V3 V4
        n.* = 4;
    }

    if (n.* == 3) {
        L[3] = L[0];
    }
    if (n.* == 4) {
        L[4] = L[0];
    }
}

fn integrateEdge(v1: Vec3, v2: Vec3) Vec3 {
    const x = Vec3.dot(v1, v2);
    const y = @abs(x);
    const a = 0.8543985 + (0.4965155 + 0.0145206 * y) * y;
    const b = 3.4175940 + (4.1616724 + y) * y;
    const v = a / b;
    const v1CrossV2 = Vec3.cross(v1, v2);
    if (x > 0.0) {
        return Vec3.multf(v1CrossV2, v);
    } else {
        const invsqrt = 1.0 / @sqrt(@max(1.0 - x * x, 1e-7));
        return Vec3.multf(v1CrossV2, 0.5 * invsqrt - v);
    }
}

fn bilinearClampSample(tex: [64 * 64]Vec4, uv_: Vec2) Vec4 {
    const uv = uv_.clamp(Vec2.init(0.0), Vec2.init(1.0));

    const tex_width: usize = 64;
    const tex_height: usize = 64;

    const tex_size = Vec2{ .x = tex_width, .y = tex_height };

    var coord = uv.multv(tex_size).sub(Vec2.init(0.5));
    coord = coord.clamp(Vec2.init(0.0), tex_size.sub(Vec2.init(1.0)));

    const base = Vec2{ .x = @floor(coord.x), .y = @floor(coord.y) };
    const frac = coord.sub(base);

    const idx0_x: i32 = @intFromFloat(base.x);
    const idx0_y: i32 = @intFromFloat(base.y);
    const idx1_x = @min(idx0_x + 1, tex_width - 1);
    const idx1_y = @min(idx0_y + 1, tex_height - 1);

    const c00 = tex[@intCast(idx0_y * 64 + idx0_x)];
    const c10 = tex[@intCast(idx0_y * 64 + idx1_x)];
    const c01 = tex[@intCast(idx1_y * 64 + idx0_x)];
    const c11 = tex[@intCast(idx1_y * 64 + idx1_x)];

    const c0 = Vec4.mix(c00, c10, frac.x);
    const c1 = Vec4.mix(c01, c11, frac.x);

    return Vec4.mix(c0, c1, frac.y);
}

// TODO: look into texture sampling
fn pbrBilinearSample(texture: TexturePBR, uv_: Vec2) PBR {
    const uv = uv_.clamp(Vec2.init(0.0), Vec2.init(1.0));

    const tex_size = Vec2{ .x = @floatFromInt(texture.width), .y = @floatFromInt(texture.height) };

    var coord = uv.multv(tex_size).sub(Vec2.init(0.5));
    coord = coord.clamp(Vec2.init(0.0), tex_size.sub(Vec2.init(1.0)));

    const base = Vec2{ .x = @floor(coord.x), .y = @floor(coord.y) };
    const frac = coord.sub(base);

    const idx0_x: i32 = @intFromFloat(base.x);
    const idx0_y: i32 = @intFromFloat(base.y);
    const idx1_x = @min(idx0_x + 1, texture.width - 1);
    const idx1_y = @min(idx0_y + 1, texture.height - 1);

    const c00 = texture.buffer[@as(usize, @intCast(idx0_y)) * texture.width + @as(usize, @intCast(idx0_x))];
    const c10 = texture.buffer[@as(usize, @intCast(idx0_y)) * texture.width + @as(usize, @intCast(idx1_x))];
    const c01 = texture.buffer[@as(usize, @intCast(idx1_y)) * texture.width + @as(usize, @intCast(idx0_x))];
    const c11 = texture.buffer[@as(usize, @intCast(idx1_y)) * texture.width + @as(usize, @intCast(idx1_x))];

    const c0 = PBR.mix(c00, c10, @floatCast(frac.x));
    const c1 = PBR.mix(c01, c11, @floatCast(frac.x));

    return PBR.mix(c0, c1, @floatCast(frac.y));
}

const lut_size = 64.0;
const lut_scale = (lut_size - 1.0) / lut_size;
const lut_bias = 0.5 / lut_size;

// https://github.com/b1skit/LTCAreaLightsGigi/blob/main/LTCAreaLightCS.hlsl
fn areaLightContribution(n: Vec3, v: Vec3, p: Vec3, mInv_: Matrix4, verts: [4]Vec3) Vec3 {
    const area_light_normal = Vec3.cross(verts[1].sub(verts[0]), verts[3].sub(verts[0]));
    const is_behind = (Vec3.dot(verts[0].sub(p), area_light_normal) > 0.0);

    const two_sided = false;
    if (is_behind and !two_sided) {
        return Vec3.init(0.0);
    }

    const t1 = Vec3.normalize(Vec3.sub(v, n.multf(Vec3.dot(v, n))));
    const t2 = Vec3.normalize(Vec3.cross(n, t1));

    const area_light_basis = Matrix4.transpose(Matrix4.fromVec3(t1, t2, n));
    const minv = Matrix4.multMatrix4(mInv_, area_light_basis);

    var l: [5]Vec3 = [5]Vec3{
        Matrix4.multVec3(minv, verts[0].sub(p)),
        Matrix4.multVec3(minv, verts[1].sub(p)),
        Matrix4.multVec3(minv, verts[2].sub(p)),
        Matrix4.multVec3(minv, verts[3].sub(p)),
        Vec3.init(0.0),
    };

    var count: usize = 0;

    clipQuadToHorizon(&l, &count);

    if (count == 0) return Vec3.init(0.0);

    l[0] = Vec3.normalize(l[0]);
    l[1] = Vec3.normalize(l[1]);
    l[2] = Vec3.normalize(l[2]);
    l[3] = Vec3.normalize(l[3]);
    l[4] = Vec3.normalize(l[4]);

    var form_factor: f32 = 0.0;
    form_factor += integrateEdge(l[0], l[1]).z;
    form_factor += integrateEdge(l[1], l[2]).z;
    form_factor += integrateEdge(l[2], l[3]).z;
    if (count >= 4) {
        form_factor += integrateEdge(l[3], l[4]).z;
    }
    if (count == 5) {
        form_factor += integrateEdge(l[4], l[0]).z;
    }

    if (two_sided) {
        form_factor = @abs(form_factor);
    } else {
        form_factor = @max(0.0, -form_factor);
    }

    return Vec3.init(form_factor);
}

pub var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();
pub var frame_buffer: RenderTargetRGBA16 = undefined;
pub var depth_buffer: RenderTargetR16 = undefined;

var scene: Scene = undefined;

var tex_width_f32: f32 = 0.0;
var tex_height_f32: f32 = 0.0;
const aspect_ratio: f32 = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

const winding_order = WindingOrder.CCW;

var camera_pos = Vec3{ .x = -3.0, .y = 1.0, .z = 0.0 };

var projection_mat: Matrix4 = undefined;
var view_mat: Matrix4 = undefined;

pub fn init() !void {
    // meshes = try Meshes.fromGLTFFile("cannon_01_2k/cannon_01_2k.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("main_sponza/NewSponza_Main_glTF_003.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("new_sponza/Untitled.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("assets/slum/Untitled.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("assets/arealight_test/Untitled.gltf", allocator);
    scene = try Scene.fromGLTFFile("assets/junkshop/thejunkshopsplashscreen.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("assets/pokedstudio/pokedstudio.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("assets/bistro/Untitled.gltf", allocator);
    frame_buffer = RenderTargetRGBA16.create(allocator, width, height);
    depth_buffer = RenderTargetR16.create(allocator, width, height);
    const c = scene.cameras.items[0];
    camera_pos = c.pos;
    view_mat = c.view_matrix;
    if (c.type == .Perspective) {
        projection_mat = Matrix4.perspectiveProjection(c.fov, aspect_ratio, 0.1, 100.0);
    } else {
        const adjusted_xmag = c.ymag * aspect_ratio;
        projection_mat = Matrix4.orthogonalProjection(-adjusted_xmag, adjusted_xmag, c.ymag, -c.ymag, 0.1, 1000.0);
    }
}

pub fn render(theta: f32, camera: usize) !void {
    frame_buffer.clearColor(0.2);
    depth_buffer.clearColor(1.0);

    const cam = scene.cameras.items[camera % scene.cameras.items.len];
    camera_pos = cam.pos;
    view_mat = cam.view_matrix;

    // const rot_mat = Matrix4.rotateY(theta);
    for (scene.meshes.items) |mesh| {
        if (!mesh.should_render) continue;
        // if (std.mem.eql(u8, mesh.name, "Cube")) continue;
        // const model_mat = Matrix4.multMatrix4(rot_mat, mesh.transform);
        _ = theta;
        const model_mat = mesh.transform;

        const model_view_mat = Matrix4.multMatrix4(view_mat, model_mat);
        const view_projection_mat = Matrix4.multMatrix4(projection_mat, model_view_mat);

        var indices_len: usize = 0;
        if (mesh.indices_16) |indice_16| {
            indices_len = indice_16.len;
        } else if (mesh.indices_32) |indice_32| {
            indices_len = indice_32.len;
        }

        // std.debug.print("Mesh name: {s}\n", .{mesh.name});
        var active_material: Material = undefined;
        if (mesh.material) |material_idx| {
            active_material = scene.materials.items[material_idx];
        } else {
            active_material = Material{
                .pbr_solid = PBRSolid{
                    .albedo = RGB{ .x = 1.0, .y = 0.0, .z = 0.0 },
                    .metallic = 0.5,
                    .roughness = 0.5,
                    .ao = 0.1,
                    .emissive = RGB{ .x = 1.0, .y = 1.0, .z = 1.0 },
                },
                .pbr_texture = null,
                .name = "Material Less",
                .tex_coord = 0,
                .type = .Solid,
            };
        }

        var i: u32 = 0;
        while (i < indices_len) : (i += 3) {
            var idx1: usize = 0;
            var idx2: usize = 0;
            var idx3: usize = 0;
            if (mesh.indices_16) |indice_16| {
                idx1 = @intCast(indice_16[i]);
                idx2 = @intCast(indice_16[i + 1]);
                idx3 = @intCast(indice_16[i + 2]);
            } else if (mesh.indices_32) |indice_32| {
                idx1 = @intCast(indice_32[i]);
                idx2 = @intCast(indice_32[i + 1]);
                idx3 = @intCast(indice_32[i + 2]);
            }

            const vert1 = Vec3{ .x = mesh.vertices[idx1 * 3 + 0], .y = mesh.vertices[idx1 * 3 + 1], .z = mesh.vertices[idx1 * 3 + 2] };
            const vert2 = Vec3{ .x = mesh.vertices[idx2 * 3 + 0], .y = mesh.vertices[idx2 * 3 + 1], .z = mesh.vertices[idx2 * 3 + 2] };
            const vert3 = Vec3{ .x = mesh.vertices[idx3 * 3 + 0], .y = mesh.vertices[idx3 * 3 + 1], .z = mesh.vertices[idx3 * 3 + 2] };

            const norm1 = Vec3{ .x = mesh.normals[idx1 * 3 + 0], .y = mesh.normals[idx1 * 3 + 1], .z = mesh.normals[idx1 * 3 + 2] };
            const norm2 = Vec3{ .x = mesh.normals[idx2 * 3 + 0], .y = mesh.normals[idx2 * 3 + 1], .z = mesh.normals[idx2 * 3 + 2] };
            const norm3 = Vec3{ .x = mesh.normals[idx3 * 3 + 0], .y = mesh.normals[idx3 * 3 + 1], .z = mesh.normals[idx3 * 3 + 2] };

            // const norm1 = Vec3.normalize(Vec3.cross(Vec3.sub(vert1, vert2), Vec3.sub(vert1, vert3)));
            // const norm2 = Vec3.normalize(Vec3.cross(Vec3.sub(vert2, vert3), Vec3.sub(vert2, vert1)));
            // const norm3 = Vec3.normalize(Vec3.cross(Vec3.sub(vert3, vert1), Vec3.sub(vert3, vert2)));

            //TODO: Instead of doing if statement, create seperate pipeline for meshes with no uvs
            var uv1: Vec2 = undefined;
            var uv2: Vec2 = undefined;
            var uv3: Vec2 = undefined;
            if (active_material.type == .Textured) {
                const mesh_uv = mesh.uvs[active_material.tex_coord];
                uv1 = Vec2{ .x = mesh_uv[idx1 * 2 + 0], .y = mesh_uv[idx1 * 2 + 1] };
                uv2 = Vec2{ .x = mesh_uv[idx2 * 2 + 0], .y = mesh_uv[idx2 * 2 + 1] };
                uv3 = Vec2{ .x = mesh_uv[idx3 * 2 + 0], .y = mesh_uv[idx3 * 2 + 1] };
            } else {
                uv1 = Vec2{ .x = 0.5, .y = 0.5 };
                uv2 = Vec2{ .x = 0.5, .y = 0.5 };
                uv3 = Vec2{ .x = 0.5, .y = 0.5 };
            }

            const tan1 = calculateTangent(vert1, vert2, vert3, uv1, uv2, uv3);
            const tan2 = calculateTangent(vert2, vert3, vert1, uv2, uv3, uv1);
            const tan3 = calculateTangent(vert3, vert1, vert2, uv3, uv1, uv2);

            const normalMatrix = Matrix4.transpose(Matrix4.invert(model_mat));

            const newNorm1 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm1));
            const newNorm2 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm2));
            const newNorm3 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm3));

            var newTan1 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan1));
            var newTan2 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan2));
            var newTan3 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan3));

            // T = normalize(T - dot(T, N) * N);
            newTan1 = Vec3.normalize(Vec3.sub(newTan1, Vec3.multf(newNorm1, Vec3.dot(newTan1, newNorm1))));
            newTan2 = Vec3.normalize(Vec3.sub(newTan2, Vec3.multf(newNorm2, Vec3.dot(newTan2, newNorm2))));
            newTan3 = Vec3.normalize(Vec3.sub(newTan3, Vec3.multf(newNorm3, Vec3.dot(newTan3, newNorm3))));

            const newBitan1 = Vec3.normalize(Vec3.cross(newTan1, newNorm1));
            const newBitan2 = Vec3.normalize(Vec3.cross(newTan2, newNorm2));
            const newBitan3 = Vec3.normalize(Vec3.cross(newTan3, newNorm3));

            const world_pos1 = Matrix4.multVec3(model_mat, vert1);
            const world_pos2 = Matrix4.multVec3(model_mat, vert2);
            const world_pos3 = Matrix4.multVec3(model_mat, vert3);

            const proj_vert1 = Matrix4.multVec4(view_projection_mat, vert1);
            const proj_vert2 = Matrix4.multVec4(view_projection_mat, vert2);
            const proj_vert3 = Matrix4.multVec4(view_projection_mat, vert3);

            var tri: Tri = undefined;
            tri.v0 = Vertex{ .position = proj_vert1, .world_position = world_pos1, .normal = newNorm1, .uv = uv1, .tangent = newTan1, .bitangent = newBitan1 };
            tri.v1 = Vertex{ .position = proj_vert2, .world_position = world_pos2, .normal = newNorm2, .uv = uv2, .tangent = newTan2, .bitangent = newBitan2 };
            tri.v2 = Vertex{ .position = proj_vert3, .world_position = world_pos3, .normal = newNorm3, .uv = uv3, .tangent = newTan3, .bitangent = newBitan3 };

            if (Vec3.dot(newNorm1, Vec3.normalize(Vec3.sub(camera_pos, Matrix4.multVec3(model_mat, vert1)))) > -0.25) {
                var clipped_triangle: [8]Tri = undefined;
                const count = clipTriangle(tri, &clipped_triangle);

                for (clipped_triangle, 0..) |triangle, t_idx| {
                    if (t_idx >= count) break;

                    const new_tri = triClipToNDC(triangle);

                    const a = Vec4.ndcToRaster(new_tri.v0.position, width, height);
                    const b = Vec4.ndcToRaster(new_tri.v1.position, width, height);
                    const c = Vec4.ndcToRaster(new_tri.v2.position, width, height);

                    if (AABB.getFrom(a.x, a.y, b.x, b.y, c.x, c.y)) |aabb| {
                        const area = edgeFunction(a, b, c.x, c.y);

                        const xf32 = @as(f32, @floatFromInt(aabb.min_x));
                        const yf32 = @as(f32, @floatFromInt(aabb.min_y));

                        var w_y0: f32 = edgeFunction(a, b, xf32, yf32);
                        var w_y1: f32 = edgeFunction(b, c, xf32, yf32);
                        var w_y2: f32 = edgeFunction(c, a, xf32, yf32);

                        const dy0 = (b.y - a.y);
                        const dy1 = (c.y - b.y);
                        const dy2 = (a.y - c.y);

                        const dx0 = (a.x - b.x);
                        const dx1 = (b.x - c.x);
                        const dx2 = (c.x - a.x);

                        var y: u32 = aabb.min_y;
                        while (y <= aabb.max_y) : (y += 1) {
                            var x: u32 = aabb.min_x;

                            var w_x0: f32 = w_y0;
                            var w_x1: f32 = w_y1;
                            var w_x2: f32 = w_y2;

                            while (x <= aabb.max_x) : (x += 1) {
                                if (windingOrderTest(winding_order, w_x0, w_x1, w_x2)) {
                                    const area0 = w_x0 / area;
                                    const area1 = w_x1 / area;
                                    const area2 = w_x2 / area;

                                    const z = (area1 * new_tri.v0.position.z + area2 * new_tri.v1.position.z + area0 * new_tri.v2.position.z);

                                    if (z < depth_buffer.getPixel(x, y)) {
                                        depth_buffer.putPixel(x, y, @floatCast(z));

                                        const one_over_w = (area1 * (1 / new_tri.v0.position.w) + area2 * (1 / new_tri.v1.position.w) + area0 * (1 / new_tri.v2.position.w));
                                        const w: f32 = 1 / one_over_w;

                                        const norx = area1 * new_tri.v0.normal.x + area2 * new_tri.v1.normal.x + area0 * new_tri.v2.normal.x;
                                        const nory = area1 * new_tri.v0.normal.y + area2 * new_tri.v1.normal.y + area0 * new_tri.v2.normal.y;
                                        const norz = area1 * new_tri.v0.normal.z + area2 * new_tri.v1.normal.z + area0 * new_tri.v2.normal.z;
                                        const frag_normal = Vec3.normalize(Vec3{ .x = norx * w, .y = nory * w, .z = norz * w });

                                        var albedo: Vec3 = Vec3.init(0.0);
                                        var normal: Vec3 = Vec3.init(0.0);
                                        var metallic: f32 = 0.0;
                                        var roughness: f32 = 0.0;
                                        var ao: f32 = 0.0;

                                        var emissive: Vec3 = Vec3.init(0.0);

                                        if (active_material.type == .Textured) {
                                            var u = area1 * new_tri.v0.uv.x + area2 * new_tri.v1.uv.x + area0 * new_tri.v2.uv.x;
                                            var v = area1 * new_tri.v0.uv.y + area2 * new_tri.v1.uv.y + area0 * new_tri.v2.uv.y;

                                            u *= w;
                                            v *= w;

                                            u = @mod(u, 1.0);
                                            v = @mod(v, 1.0);

                                            const tex_uv = Vec2{ .x = u, .y = v };

                                            const tangentx = area1 * new_tri.v0.tangent.x + area2 * new_tri.v1.tangent.x + area0 * new_tri.v2.tangent.x;
                                            const tangenty = area1 * new_tri.v0.tangent.y + area2 * new_tri.v1.tangent.y + area0 * new_tri.v2.tangent.y;
                                            const tangentz = area1 * new_tri.v0.tangent.z + area2 * new_tri.v1.tangent.z + area0 * new_tri.v2.tangent.z;
                                            const tangent = Vec3.normalize(Vec3{ .x = tangentx * w, .y = tangenty * w, .z = tangentz * w });

                                            const bitangentx = area1 * new_tri.v0.bitangent.x + area2 * new_tri.v1.bitangent.x + area0 * new_tri.v2.bitangent.x;
                                            const bitangenty = area1 * new_tri.v0.bitangent.y + area2 * new_tri.v1.bitangent.y + area0 * new_tri.v2.bitangent.y;
                                            const bitangentz = area1 * new_tri.v0.bitangent.z + area2 * new_tri.v1.bitangent.z + area0 * new_tri.v2.bitangent.z;
                                            const bitangent = Vec3.normalize(Vec3{ .x = bitangentx * w, .y = bitangenty * w, .z = bitangentz * w });

                                            const pbr = pbrBilinearSample(active_material.pbr_texture.?, tex_uv);
                                            albedo = Vec3{ .x = @floatCast(pbr.albedo.x), .y = @floatCast(pbr.albedo.y), .z = @floatCast(pbr.albedo.z) };

                                            var normal_map = Vec3{ .x = @floatCast(pbr.normal.x), .y = @floatCast(pbr.normal.y), .z = @floatCast(pbr.normal.z) };
                                            normal_map = Vec3.normalize(normal_map);

                                            metallic = @floatCast(pbr.metallic);
                                            roughness = @floatCast(pbr.roughness);
                                            ao = @floatCast(pbr.ao);
                                            emissive = Vec3{ .x = pbr.emissive.x, .y = pbr.emissive.y, .z = pbr.emissive.z };

                                            normal = Vec3.add(Vec3.multf(tangent, normal_map.x), Vec3.add(Vec3.multf(bitangent, normal_map.y), Vec3.multf(frag_normal, normal_map.z)));
                                            normal = Vec3.normalize(normal);
                                        } else {
                                            const pbr_solid = active_material.pbr_solid.?;
                                            albedo = Vec3{ .x = @floatCast(pbr_solid.albedo.x), .y = @floatCast(pbr_solid.albedo.y), .z = @floatCast(pbr_solid.albedo.z) };
                                            normal = frag_normal;
                                            metallic = @floatCast(pbr_solid.metallic);
                                            roughness = @floatCast(pbr_solid.roughness);
                                            ao = @floatCast(pbr_solid.ao);

                                            emissive = Vec3{ .x = @floatCast(pbr_solid.emissive.x), .y = @floatCast(pbr_solid.emissive.y), .z = @floatCast(pbr_solid.emissive.z) };
                                        }

                                        const worldx = area1 * new_tri.v0.world_position.x + area2 * new_tri.v1.world_position.x + area0 * new_tri.v2.world_position.x;
                                        const worldy = area1 * new_tri.v0.world_position.y + area2 * new_tri.v1.world_position.y + area0 * new_tri.v2.world_position.y;
                                        const worldz = area1 * new_tri.v0.world_position.z + area2 * new_tri.v1.world_position.z + area0 * new_tri.v2.world_position.z;
                                        const world = Vec3{ .x = worldx * w, .y = worldy * w, .z = worldz * w };

                                        const view_dir = Vec3.normalize(Vec3.sub(camera_pos, world));

                                        var Lo: Vec3 = Vec3.init(0.0);

                                        var f0 = Vec3{ .x = 0.04, .y = 0.04, .z = 0.04 };
                                        f0 = Vec3.mix(f0, albedo, metallic);

                                        for (scene.lights.items) |light| {
                                            if (light.type == .Area) {
                                                const dotNV = std.math.clamp(Vec3.dot(normal, view_dir), 0.0, 1.0);

                                                var uv = Vec2{ .x = roughness, .y = @sqrt(1.0 - dotNV) };
                                                uv = uv.multf(lut_scale).add(Vec2{ .x = lut_bias, .y = lut_bias });

                                                const t1 = bilinearClampSample(LTC1, uv);
                                                const t2 = bilinearClampSample(LTC2, uv);

                                                const mInv = Matrix4.fromVec3(
                                                    Vec3{ .x = t1.x, .y = 0.0, .z = t1.y },
                                                    Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 },
                                                    Vec3{ .x = t1.z, .y = 0.0, .z = t1.w },
                                                );

                                                var verts: [4]Vec3 = undefined;
                                                // verts[0] = Matrix4.multVec3(rot_mat, light.verts.?[0]);
                                                // verts[1] = Matrix4.multVec3(rot_mat, light.verts.?[1]);
                                                // verts[2] = Matrix4.multVec3(rot_mat, light.verts.?[2]);
                                                // verts[3] = Matrix4.multVec3(rot_mat, light.verts.?[3]);
                                                verts[0] = light.verts.?[0];
                                                verts[1] = light.verts.?[1];
                                                verts[2] = light.verts.?[2];
                                                verts[3] = light.verts.?[3];

                                                const diffuse = areaLightContribution(normal, view_dir, world, Matrix4.getIdentity(), verts);
                                                var specular = areaLightContribution(normal, view_dir, world, mInv, verts);

                                                const fresnel = Vec3{
                                                    .x = f0.x * t2.x + (1.0 - f0.x) * t2.y,
                                                    .y = f0.y * t2.x + (1.0 - f0.y) * t2.y,
                                                    .z = f0.z * t2.x + (1.0 - f0.z) * t2.y,
                                                };

                                                specular = specular.multv(fresnel);
                                                const kD = Vec3.init(1.0 - metallic);

                                                const l_diffuse = kD.multv(albedo.multv(diffuse).multf(1.0 / std.math.pi));
                                                const radiance = light.color;
                                                const Lo1 = Vec3.add(specular, l_diffuse).multv(radiance);

                                                Lo = Lo.add(Lo1);
                                            } else {
                                                var light_dir: Vec3 = Vec3.init(0.0);
                                                var radiance: Vec3 = Vec3.init(0.0);
                                                if (light.type == .Directional) {
                                                    light_dir = Vec3.normalize(light.pos);
                                                    light_dir = Vec3.multf(light_dir, -1.0);
                                                    radiance = light.color.multf(light.intensity);
                                                } else if (light.type == .Point) {
                                                    light_dir = Vec3.normalize(Vec3.sub(light.pos, world));
                                                    const distance = Vec3.getLength(Vec3.sub(light.pos, world));
                                                    const attenuation = 1.0 / (distance * distance + 1.0);

                                                    radiance = Vec3.multf(light.color.multf(light.intensity), attenuation);
                                                }
                                                const half_vec = Vec3.normalize(Vec3.add(light_dir, view_dir));

                                                const fresnel: Vec3 = fresnelSchlick(f0, @max(Vec3.dot(half_vec, view_dir), 0.0));

                                                const normal_distr: f32 = normalDistributionGGX(normal, half_vec, roughness);
                                                const geometryS: f32 = geometrySmith(normal, view_dir, light_dir, roughness);

                                                const numerator: Vec3 = fresnel.multf(geometryS * normal_distr);
                                                const denominator: f32 = 4.0 * @max(Vec3.dot(normal, view_dir), 0.0) * @max(Vec3.dot(normal, light_dir), 0.0) + 0.0001;
                                                const specular: Vec3 = numerator.multf(1 / denominator);

                                                const kS: Vec3 = fresnel;
                                                var kD: Vec3 = Vec3.init(1.0).sub(kS);

                                                kD = kD.multf(1.0 - metallic);

                                                const NdotL: f32 = @max(Vec3.dot(normal, light_dir), 0.0);
                                                const Lo1 = Vec3.multv(kD, Vec3.multf(albedo, 1.0 / std.math.pi));
                                                const Lo2 = Vec3.add(Lo1, specular);
                                                Lo = Vec3.add(Lo, Vec3.multv(Lo2, radiance).multf(NdotL));
                                            }
                                        }
                                        // const ambient = Vec3.init(0.03).multv(albedo).multf(ao);
                                        // var color = Vec3.add(ambient, Lo);
                                        var color = Lo;
                                        color = color.add(emissive);
                                        color = color.divv(color.add(Vec3.init(1.0)));
                                        color = color.pow(Vec3.init(1.0 / 2.2));

                                        frame_buffer.putPixel(x, y, Color{ .r = @floatCast(color.x), .g = @floatCast(color.y), .b = @floatCast(color.z) });
                                    }
                                }
                                w_x0 += dy0;
                                w_x1 += dy1;
                                w_x2 += dy2;
                            }
                            w_y0 += dx0;
                            w_y1 += dx1;
                            w_y2 += dx2;
                        }
                    }
                }
            }
        }
    }
}

pub fn deinit() void {
    // mesh.deinit(allocator);
    // TODO: Deallocate name strings and textures/materials in mesh.zig and material.zig
    // texture_pbr.deinit(allocator);
    scene.deinit(allocator);
    frame_buffer.deinit();
    depth_buffer.deinit();
    arena.deinit();
}
