const std = @import("std");
const Vec3 = @import("vec3.zig").Vec3;

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

    pub fn multMatrix4(a: Matrix4, b: Matrix4) Matrix4 {
        var out_mat = getZero();

        var x: u8 = 0;
        var y: u8 = 0;
        var i: u8 = 1;
        var t: f32 = 0;

        while (x < 4) : (x += 1) {
            while (y < 4) : (y += 1) {
                t = getMatrix4(a, 0, y) * getMatrix4(b, x, 0);
                while (i < 4) : (i += 1) {
                    t += getMatrix4(a, i, y) * getMatrix4(b, x, i);
                }
                setMatrix4(&out_mat, x, y, t);
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
        var w: f32 = vec.x * mat.mat[12] + vec.y * mat.mat[13] + vec.z * mat.mat[14] + mat.mat[15];

        if (w != 1.0) {
            out_vec.x /= w;
            out_vec.y /= w;
            out_vec.z /= w;
        }
        return out_vec;
    }

    pub fn lookAt(from: Vec3, to: Vec3, up: Vec3) Matrix4 {
        var out_mat: Matrix4 = getZero();

        var forward: Vec3 = Vec3.normalize(Vec3.sub(to, from));
        var right: Vec3 = Vec3.normalize(Vec3.cross(forward, up));
        var new_up: Vec3 = Vec3.cross(right, forward);
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
        out_mat.mat[12] = 0;
        out_mat.mat[13] = 0;
        out_mat.mat[14] = 0;
        out_mat.mat[15] = 1;

        return out_mat;
    }

    pub fn perspectiveProjection(fov: f32, aspect: f32, near: f32, far: f32) Matrix4 {
        var out_mat: Matrix4 = getZero();

        var scale_height: f32 = 1.0 / @tan(fov / 2.0);
        var scale_width: f32 = scale_height / aspect;

        out_mat.mat[0] = scale_width;
        out_mat.mat[5] = scale_height;
        out_mat.mat[10] = (far + near) / (near - far);
        out_mat.mat[11] = 2.0 * far * near / (near - far);
        out_mat.mat[14] = -1.0;

        return out_mat;
    }

    pub fn orthogonalProjection(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) Matrix4 {
        var out_mat: Matrix4 = getZero();

        var rl = right - left;
        var tb = top - bottom;
        var f_n = far - near;
        var tx = -(right + left) / (rl);
        var ty = -(top + bottom) / (tb);
        var tz = -(far + near) / (f_n);

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
        var mat = [4 * 4]f32{ @cos(theta), 0, @sin(theta), 0, 0, 1, 0, 0, -@sin(theta), 0, @cos(theta), 0, 0, 0, 0, 1 };
        var out_mat = Matrix4{ .mat = mat };
        return out_mat;
    }
};
