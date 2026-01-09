const std = @import("std");
const Vec4 = @import("../math/vec4.zig").Vec4;
const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec2 = @import("../math/vec2.zig").Vec2;
const Matrix4 = @import("../math/matrix4.zig").Matrix4;
const PBRTexture = @import("../utils/texture.zig").PBRTexture;
const PBR = @import("../utils/texture.zig").PBR;

// LTC's LUT
const lut_size = 64.0;
pub const lut_scale = (lut_size - 1.0) / lut_size;
pub const lut_bias = 0.5 / lut_size;

pub fn fresnelSchlick(f0: Vec3, cosTheta: f32) Vec3 {
    // F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
    // return F0 + (1.0 - F0)*pow((1.0 + 0.000001/*avoid negative approximation when cosTheta = 1*/) - cosTheta, 5.0);
    const c = std.math.pow(f32, 1.0 + 0.000001 - cosTheta, 5.0);
    return Vec3{
        .x = f0.x + (1.0 - f0.x) * c,
        .y = f0.y + (1.0 - f0.y) * c,
        .z = f0.z + (1.0 - f0.z) * c,
    };
}

pub fn normalDistributionGGX(normal: Vec3, half_vec: Vec3, roughness: f32) f32 {
    const a: f32 = roughness * roughness;
    const a2: f32 = a * a;
    const ndotH: f32 = @max(Vec3.dot(normal, half_vec), 0.0);
    const ndotH2: f32 = ndotH * ndotH;

    const num: f32 = a2;
    var denom: f32 = (ndotH2 * (a2 - 1.0) + 1.0);
    denom = std.math.pi * denom * denom;

    return num / denom;
}

pub fn geometrySchlickGGX(ndotV: f32, roughness: f32) f32 {
    const r: f32 = (roughness + 1.0);
    const k: f32 = (r * r) / 8.0;

    const num: f32 = ndotV;
    const denom: f32 = ndotV * (1.0 - k) + k;

    return num / denom;
}

pub fn geometrySmith(normal: Vec3, view_dir: Vec3, light_dir: Vec3, roughness: f32) f32 {
    const ndotV: f32 = @max(Vec3.dot(normal, view_dir), 0.0);
    const ndotL: f32 = @max(Vec3.dot(normal, light_dir), 0.0);
    const ggx2: f32 = geometrySchlickGGX(ndotV, roughness);
    const ggx1: f32 = geometrySchlickGGX(ndotL, roughness);

    return ggx1 * ggx2;
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

pub fn bilinearClampSample(tex: [64 * 64]Vec4, uv_: Vec2) Vec4 {
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

    const c0 = Vec4.lerp(c00, c10, frac.x);
    const c1 = Vec4.lerp(c01, c11, frac.x);

    return Vec4.lerp(c0, c1, frac.y);
}

// TODO: look into texture sampling
pub fn pbrBilinearSample(texture: PBRTexture, uv_: Vec2) PBR {
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

    const c0 = PBR.lerp(c00, c10, @floatCast(frac.x));
    const c1 = PBR.lerp(c01, c11, @floatCast(frac.x));

    return PBR.lerp(c0, c1, @floatCast(frac.y));
}

// https://github.com/b1skit/LTCAreaLightsGigi/blob/main/LTCAreaLightCS.hlsl
pub fn areaLightContribution(n: Vec3, v: Vec3, p: Vec3, mInv_: Matrix4, verts: [4]Vec3) Vec3 {
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
