const std = @import("std");
const Vec3 = @import("vec3.zig").Vec3;
const Vec4 = @import("vec4.zig").Vec4;

pub const Matrix4 = struct {
    mat: [4 * 4]f32,

    fn getZero() Matrix4 {
        const out_mat = [4 * 4]f32{
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
        };
        return Matrix4{ .mat = out_mat };
    }

    pub fn getIdentity() Matrix4 {
        const out_mat = [4 * 4]f32{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        };
        return Matrix4{ .mat = out_mat };
    }

    pub fn getMatrix4(mat: Matrix4, x: u32, y: u32) f32 {
        return mat.mat[y * 4 + x];
    }

    pub fn setMatrix4(mat: *Matrix4, x: u32, y: u32, val: f32) void {
        mat.mat[y * 4 + x] = val;
    }

    // pub fn fromVec3(a: Vec3, b: Vec3, c: Vec3) Matrix4 {
    //  const out_mat = [4 * 4]f32{
    //      a.x, a.y, a.z, 0,
    //      b.x, b.y, b.z, 0,
    //      c.x, c.y, c.z, 0,
    //      0, 0, 0, 1,
    //  };
    //  return Matrix4{ .mat = out_mat };
    // }

    pub fn fromVec3(a: Vec3, b: Vec3, c: Vec3) Matrix4 {
        // Creates a matrix with a, b, c as COLUMNS (not rows)
        const out_mat = [4 * 4]f32{
            a.x, b.x, c.x, 0, // Row 0: first components of each vector
            a.y, b.y, c.y, 0, // Row 1: second components of each vector
            a.z, b.z, c.z, 0, // Row 2: third components of each vector
            0, 0, 0, 1, // Row 3: homogeneous coordinate
        };
        return Matrix4{ .mat = out_mat };
    }

    pub fn multMatrix4(a: Matrix4, b: Matrix4) Matrix4 {
        var out_mat = comptime getZero();

        var x: u8 = 0;
        var y: u8 = 0;
        var i: u8 = 1;
        var t: f32 = 0;

        while (x < 4) : (x += 1) {
            while (y < 4) : (y += 1) {
                t = a.mat[y * 4 + 0] * b.mat[0 * 4 + x];
                while (i < 4) : (i += 1) {
                    t += a.mat[y * 4 + i] * b.mat[i * 4 + x];
                }
                out_mat.mat[y * 4 + x] = t;
                i = 1;
            }
            y = 0;
        }

        return out_mat;
    }

    pub fn multVec3(mat: Matrix4, vec: Vec3) Vec3 {
        var out_vec: Vec3 = Vec3{};
        out_vec.x = vec.x * mat.mat[0] + vec.y * mat.mat[1] + vec.z * mat.mat[2] + mat.mat[3];
        out_vec.y = vec.x * mat.mat[4] + vec.y * mat.mat[5] + vec.z * mat.mat[6] + mat.mat[7];
        out_vec.z = vec.x * mat.mat[8] + vec.y * mat.mat[9] + vec.z * mat.mat[10] + mat.mat[11];
        const w: f32 = vec.x * mat.mat[12] + vec.y * mat.mat[13] + vec.z * mat.mat[14] + mat.mat[15];

        // if (w != 1.0) {
        out_vec.x /= w;
        out_vec.y /= w;
        out_vec.z /= w;
        // }
        return out_vec;
    }

    pub fn multVec4(mat: Matrix4, vec: Vec3) Vec4 {
        var out_vec: Vec4 = Vec4{};
        out_vec.x = vec.x * mat.mat[0] + vec.y * mat.mat[1] + vec.z * mat.mat[2] + mat.mat[3];
        out_vec.y = vec.x * mat.mat[4] + vec.y * mat.mat[5] + vec.z * mat.mat[6] + mat.mat[7];
        out_vec.z = vec.x * mat.mat[8] + vec.y * mat.mat[9] + vec.z * mat.mat[10] + mat.mat[11];
        out_vec.w = vec.x * mat.mat[12] + vec.y * mat.mat[13] + vec.z * mat.mat[14] + mat.mat[15];

        // if (w != 1.0) {
        // out_vec.x /= w;
        // out_vec.y /= w;
        // out_vec.z /= w;
        // }
        return out_vec;
    }

    pub fn lookAt(from: Vec3, to: Vec3, up: Vec3) Matrix4 {
        var out_mat: Matrix4 = comptime getZero();

        const forward: Vec3 = Vec3.normalize(Vec3.sub(to, from));
        const right: Vec3 = Vec3.normalize(Vec3.cross(forward, up));
        const new_up: Vec3 = Vec3.cross(right, forward);
        out_mat.mat[0] = right.x;
        out_mat.mat[1] = right.y;
        out_mat.mat[2] = right.z;
        out_mat.mat[3] = -Vec3.dot(right, from);
        out_mat.mat[4] = new_up.x;
        out_mat.mat[5] = new_up.y;
        out_mat.mat[6] = new_up.z;
        out_mat.mat[7] = -Vec3.dot(new_up, from);
        out_mat.mat[8] = -forward.x;
        out_mat.mat[9] = -forward.y;
        out_mat.mat[10] = -forward.z;
        out_mat.mat[11] = Vec3.dot(forward, from);
        out_mat.mat[15] = 1;

        return out_mat;
    }

    pub fn perspectiveProjection(fov: f32, aspect: f32, near: f32, far: f32) Matrix4 {
        var out_mat: Matrix4 = comptime getZero();

        const scale_height: f32 = 1.0 / @tan(fov / 2.0);
        const scale_width: f32 = scale_height / aspect;

        out_mat.mat[0] = scale_width;
        out_mat.mat[5] = scale_height;
        out_mat.mat[10] = (far + near) / (near - far);
        out_mat.mat[11] = 2.0 * far * near / (near - far);
        out_mat.mat[14] = -1.0;

        return out_mat;
    }

    pub fn orthogonalProjection(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) Matrix4 {
        var out_mat: Matrix4 = comptime getZero();

        const rl = right - left;
        const tb = top - bottom;
        const f_n = far - near;
        const tx = -(right + left) / (rl);
        const ty = -(top + bottom) / (tb);
        const tz = -(far + near) / (f_n);

        out_mat.mat[0] = 2 / rl;
        out_mat.mat[3] = tx;
        out_mat.mat[5] = 2 / tb;
        out_mat.mat[7] = ty;
        out_mat.mat[10] = -2 / f_n;
        out_mat.mat[11] = tz;
        out_mat.mat[15] = 1.0;

        return out_mat;
    }

    pub fn rotateY(theta: f32) Matrix4 {
        var out_mat: Matrix4 = comptime getZero();

        const ct = @cos(theta);
        const st = @sin(theta);

        out_mat.mat[0] = ct;
        out_mat.mat[2] = st;
        out_mat.mat[5] = 1;
        out_mat.mat[8] = -st;
        out_mat.mat[10] = ct;
        out_mat.mat[15] = 1;

        return out_mat;
    }

    //TODO: Check both of transpose and invert code

    pub fn transpose(mat: Matrix4) Matrix4 {
        var out_mat: Matrix4 = undefined;

        var x: u8 = 0;
        var y: u8 = 0;

        while (y < 4) : (y += 1) {
            while (x < 4) : (x += 1) {
                out_mat.mat[y * 4 + x] = mat.mat[x * 4 + y];
            }
            x = 0;
        }

        return out_mat;
    }

    pub fn invert(mat: Matrix4) Matrix4 {
        var out_mat: Matrix4 = undefined;
        const m = mat.mat;

        // Calculate 2x2 sub-determinants for the first two columns
        const s0 = m[0] * m[5] - m[4] * m[1];
        const s1 = m[0] * m[6] - m[4] * m[2];
        const s2 = m[0] * m[7] - m[4] * m[3];
        const s3 = m[1] * m[6] - m[5] * m[2];
        const s4 = m[1] * m[7] - m[5] * m[3];
        const s5 = m[2] * m[7] - m[6] * m[3];

        // Calculate 2x2 sub-determinants for the last two columns
        const c5 = m[10] * m[15] - m[14] * m[11];
        const c4 = m[9] * m[15] - m[13] * m[11];
        const c3 = m[9] * m[14] - m[13] * m[10];
        const c2 = m[8] * m[15] - m[12] * m[11];
        const c1 = m[8] * m[14] - m[12] * m[10];
        const c0 = m[8] * m[13] - m[12] * m[9];

        // Calculate determinant
        const det = s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0;

        // Check if matrix is invertible
        // if (@abs(det) < 1e-8) {
        // return null;
        // }

        const inv_det = 1.0 / det;

        // Calculate inverse using cofactor method
        out_mat.mat[0] = (m[5] * c5 - m[6] * c4 + m[7] * c3) * inv_det;
        out_mat.mat[1] = (-m[1] * c5 + m[2] * c4 - m[3] * c3) * inv_det;
        out_mat.mat[2] = (m[13] * s5 - m[14] * s4 + m[15] * s3) * inv_det;
        out_mat.mat[3] = (-m[9] * s5 + m[10] * s4 - m[11] * s3) * inv_det;

        out_mat.mat[4] = (-m[4] * c5 + m[6] * c2 - m[7] * c1) * inv_det;
        out_mat.mat[5] = (m[0] * c5 - m[2] * c2 + m[3] * c1) * inv_det;
        out_mat.mat[6] = (-m[12] * s5 + m[14] * s2 - m[15] * s1) * inv_det;
        out_mat.mat[7] = (m[8] * s5 - m[10] * s2 + m[11] * s1) * inv_det;

        out_mat.mat[8] = (m[4] * c4 - m[5] * c2 + m[7] * c0) * inv_det;
        out_mat.mat[9] = (-m[0] * c4 + m[1] * c2 - m[3] * c0) * inv_det;
        out_mat.mat[10] = (m[12] * s4 - m[13] * s2 + m[15] * s0) * inv_det;
        out_mat.mat[11] = (-m[8] * s4 + m[9] * s2 - m[11] * s0) * inv_det;

        out_mat.mat[12] = (-m[4] * c3 + m[5] * c1 - m[6] * c0) * inv_det;
        out_mat.mat[13] = (m[0] * c3 - m[1] * c1 + m[2] * c0) * inv_det;
        out_mat.mat[14] = (-m[12] * s3 + m[13] * s1 - m[14] * s0) * inv_det;
        out_mat.mat[15] = (m[8] * s3 - m[9] * s1 + m[10] * s0) * inv_det;

        return out_mat;
    }

    pub fn print(self: Matrix4) void {
        std.debug.print("Mat4: {any}\n\n", .{self});
    }
};
