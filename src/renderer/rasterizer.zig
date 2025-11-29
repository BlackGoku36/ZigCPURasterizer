const std = @import("std");
const zigimg = @import("zigimg");
const obj = @import("zig-obj");

const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec4 = @import("../math/vec4.zig").Vec4;
const Vec2 = @import("../math/vec2.zig").Vec2;
const Matrix4 = @import("../math/matrix4.zig").Matrix4;

const rendertarget = @import("rendertarget.zig");
const RenderTargetRGBA16 = rendertarget.RenderTargetRGBA16;
const RenderTargetR16 = rendertarget.RenderTargetR16;
const Color = rendertarget.Color;

const Mesh = @import("../mesh.zig").Mesh;

pub const width = 1280;
pub const height = 720;

const WindingOrder = enum { CW, CCW };
const ClippingPlane = enum(u8) {NEAR, FAR, LEFT, RIGHT, TOP, BOTTOM};
const Vertex = struct {
	position: Vec4,
	world_position: Vec3,
	normal: Vec3,
	uv: Vec2,
};
const Tri = struct{
	v0: Vertex,
	v1: Vertex,
	v2: Vertex,
};
const Polygon = struct {
	vertices: [10]Vertex,
	count: u8
};
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
		.BOTTOM => return vertex.y >= -vertex.w
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
	if(polygon_in.count == 0) return;

	polygon_out.count = 0;

	var prev: Vertex = polygon_in.vertices[polygon_in.count - 1];
	var prev_inside: bool = insidePlane(prev, plane);

	for(0..polygon_in.count) | i |{
		const curr: Vertex = polygon_in.vertices[i];
		const curr_inside: bool = insidePlane(curr, plane);

		if(curr_inside){
			if(!prev_inside){
				const t = intersectPlane(prev, curr, plane);
				polygon_out.vertices[polygon_out.count] = lerpVertex(prev, curr, t);
				polygon_out.count += 1;
			}
			polygon_out.vertices[polygon_out.count] = curr;
			polygon_out.count += 1;
		}else if(prev_inside){
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

	for(0..6) | i |{
		const e:ClippingPlane = @enumFromInt(i);
		clipPolygonAgainstPlane(input, output, e);

		if(output.count == 0){
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
	var polygon_in: Polygon = Polygon{
		.count = 3,
		.vertices = .{tri_in.v0, tri_in.v1, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2, tri_in.v2}
	};

	const vertex_count = clipPolygonAgainstAllPlane(&polygon_in);
	if(vertex_count < 3) return 0;

	const tri_count = vertex_count - 2;
    for (0..tri_count) | i | {
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
	const nor = vertex.normal;
	const uv = vertex.uv;
	const one_over_w = 1.0 / pos.w;
	return Vertex{
		.position = Vec4{.x = pos.x / pos.w, .y = pos.y / pos.w, .z = pos.z / pos.w, .w = pos.w},
		.world_position = Vec3{.x = world_pos.x * one_over_w, .y = world_pos.y * one_over_w, .z = world_pos.z * one_over_w},
		.normal = Vec3{.x = nor.x * one_over_w, .y = nor.y * one_over_w, .z = nor.z * one_over_w},
		.uv = Vec2{.x = uv.x * one_over_w, .y = uv.y * one_over_w},
	};
}

fn triClipToNDC(tri: Tri) Tri {
	return Tri{
		.v0 = vertexClipToNDC(tri.v0),
		.v1 = vertexClipToNDC(tri.v1),
		.v2 = vertexClipToNDC(tri.v2),
	};
}

pub var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();
pub var frame_buffer: RenderTargetRGBA16 = undefined;
pub var depth_buffer: RenderTargetR16 = undefined;

var mesh: Mesh = undefined;

var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
var albedo_tex: zigimg.Image = undefined;

var tex_width_f32: f32 = 0.0;
var tex_height_f32: f32 = 0.0;
const aspect_ratio: f32 = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

const winding_order = WindingOrder.CCW;

const light_from = Vec3{ .x = 0.0, .y = 3.0, .z = 0.0 };
const light_to = Vec3{ .x = 30.0, .y = 2.0, .z = 0.0 };

const from = Vec3{.x = -0.7, .y = 0.2, .z = 0.0 };
const to = Vec3{ .x = 0.0, .y = 0.2, .z = 0.0 };
const up = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };

const projection_mat = Matrix4.perspectiveProjection(45.0, aspect_ratio, 0.1, 100.0);
const view_mat = Matrix4.lookAt(from, to, up);

pub fn init() !void {
    frame_buffer = RenderTargetRGBA16.create(allocator, width, height);
    depth_buffer = RenderTargetR16.create(allocator, width, height);
    mesh = try Mesh.fromObjFile("lion_head_2k.obj", allocator);
    albedo_tex = try zigimg.Image.fromFilePath(allocator, "lion_head_diff_2k.png", albedo_read_buffer[0..]);
    tex_width_f32 = @floatFromInt(albedo_tex.width);
    tex_height_f32 = @floatFromInt(albedo_tex.height);
}

pub fn render(theta: f32) !void {
    frame_buffer.clearColor(0.5);
    depth_buffer.clearColor(1.0);

    const model_mat = Matrix4.rotateY(theta);

    const model_view_mat = Matrix4.multMatrix4(view_mat, model_mat);
    const view_projection_mat = Matrix4.multMatrix4(projection_mat, model_view_mat);

    var i: u32 = 0;
    while (i < mesh.indices) : (i += 3) {
        const vert1 = mesh.vertices.items[i];
        const vert2 = mesh.vertices.items[i + 1];
        const vert3 = mesh.vertices.items[i + 2];

        const norm1 = mesh.normals.items[i];
        const norm2 = mesh.normals.items[i+1];
        const norm3 = mesh.normals.items[i+2];

        const newNorm1 = Matrix4.multVec3(model_mat, norm1);
        const newNorm2 = Matrix4.multVec3(model_mat, norm2);
        const newNorm3 = Matrix4.multVec3(model_mat, norm3);

        const world_pos1 = Matrix4.multVec3(model_mat, vert1);
        const world_pos2 = Matrix4.multVec3(model_mat, vert2);
        const world_pos3 = Matrix4.multVec3(model_mat, vert3);

        const uv1 = mesh.uvs.items[i];
        const uv2 = mesh.uvs.items[i+1];
        const uv3 = mesh.uvs.items[i+2];

        const proj_vert1 = Matrix4.multVec4(view_projection_mat, vert1);
        const proj_vert2 = Matrix4.multVec4(view_projection_mat, vert2);
        const proj_vert3 = Matrix4.multVec4(view_projection_mat, vert3);

        var tri: Tri = undefined;
        tri.v0 = Vertex{.position = proj_vert1, .world_position = world_pos1, .normal = newNorm1, .uv = uv1};
        tri.v1 = Vertex{.position = proj_vert2, .world_position = world_pos2, .normal = newNorm2, .uv = uv2};
        tri.v2 = Vertex{.position = proj_vert3, .world_position = world_pos3, .normal = newNorm3, .uv = uv3};

        // if (Vec3.dot(newNorm1, Vec3.normalize(Vec3.sub(from, Matrix4.multVec3(model_mat, vert1)))) > -0.25) {

        var clipped_triangle: [8]Tri = undefined;
        const count = clipTriangle(tri, &clipped_triangle);

        for (clipped_triangle, 0..) |triangle, t_idx| {
        	if(t_idx >= count) break;

            const light_dir = Vec3.normalize(Vec3.sub(light_from, light_to));

            // const normal = Vec3.cross(Vec3.sub(b_rot, a_rot), Vec3.sub(c_rot, a_rot)).normalize();
            // const normal = triangle.v0.normal;

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

                                const one_over_w = (area1 * (1/new_tri.v0.position.w) + area2 * (1/new_tri.v1.position.w) + area0 * (1/new_tri.v2.position.w));
                                const w:f32 = 1/one_over_w;

                                var u = area1 * new_tri.v0.uv.x + area2 * new_tri.v1.uv.x + area0 * new_tri.v2.uv.x;
                                var v = area1 * new_tri.v0.uv.y + area2 * new_tri.v1.uv.y + area0 * new_tri.v2.uv.y;

                                u *= w;
                                v *= w;

                                u = std.math.clamp(u, 0.0, 1.0);
                                v = std.math.clamp(v, 0.0, 1.0);

                                // WHYYYYYYYYYYYYYY!!!!!!
                                v = 1.0 - v;

                                const tex_u: u32 = @intFromFloat(u * tex_width_f32);
                                const tex_v: u32 = @intFromFloat(v * tex_height_f32);

                                var albedo = albedo_tex.pixels.rgb48[tex_v * albedo_tex.width + tex_u].to.float4();

                                // var u = area1 * a_uv.x + area2 * b_uv.x + area0 * c_uv.x;
                                // var v = area1 * a_uv.y + area2 * b_uv.y + area0 * c_uv.y;
                                const norx = area1 * new_tri.v0.normal.x + area2 * new_tri.v1.normal.x + area0 * new_tri.v2.normal.x;
                                const nory = area1 * new_tri.v0.normal.y + area2 * new_tri.v1.normal.y + area0 * new_tri.v2.normal.y;
                                const norz = area1 * new_tri.v0.normal.z + area2 * new_tri.v1.normal.z + area0 * new_tri.v2.normal.z;
                                const normal = Vec3.normalize(Vec3{.x = norx*w, .y = nory*w, .z = norz*w});

                                // const worldx = area1 * new_tri.v0.world_position.x + area2 * new_tri.v1.world_position.x + area0 * new_tri.v2.world_position.x;
                                // const worldy = area1 * new_tri.v0.world_position.y + area2 * new_tri.v1.world_position.y + area0 * new_tri.v2.world_position.y;
                                // const worldz = area1 * new_tri.v0.world_position.z + area2 * new_tri.v1.world_position.z + area0 * new_tri.v2.world_position.z;
                                // const world = Vec3{.x = worldx*w, .y = worldy*w, .z = worldz*w};

                                // const view_dir = Vec3.normalize(Vec3.sub(from, world));
                                // const half_vector = Vec3.add(light_dir, view_dir);

                                // const distance:f32 = 1000000000.0;// length(from - world)
                                // const attenuation = 1/distance;
                                // const radiance = Vec3.multf(Vec3{.x = 1.0, .y = 1.0, .z = 1.0}, attenuation); // light_col * attenuation


                                // var albedo: [3]f32 = .{1.0, 1.0, 1.0};

                                const pong = @max(0.0, Vec3.dot(normal, light_dir));

                                // albedo[0] = world.x;
                                // albedo[1] = world.y;
                                // albedo[2] = world.z;

                                albedo[0] *= pong;
                                albedo[1] *= pong;
                                albedo[2] *= pong;

                                frame_buffer.putPixel(x, y, Color{ .r = @floatCast(albedo[0]), .g = @floatCast(albedo[1]), .b = @floatCast(albedo[2]) });
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
        // }
    }
}

pub fn deinit() void {
    mesh.deinit(allocator);
    albedo_tex.deinit(allocator);
    frame_buffer.deinit();
    depth_buffer.deinit();
    arena.deinit();
}
