const std = @import("std");
const Vec3 = @import("vec3.zig").Vec3;
const Matrix4 = @import("matrix4.zig").Matrix4;

pub const Quat = struct {
    c: Vec3,
    r: f32,

    pub fn conjugate(q: Quat) Quat {
        var v = q.c;
        v.x = -v.x;
        v.y = -v.y;
        v.z = -v.z;
        return Quat{
            .c = v,
            .r = q.r,
        };
    }

    pub fn mat4FromQuat(q: Quat) Matrix4 {
        const a = q.r;
        const b = q.c.x;
        const c = q.c.y;
        const d = q.c.z;
        const a2 = a * a;
        const b2 = b * b;
        const c2 = c * c;
        const d2 = d * d;

        var mat = Matrix4.getIdentity();

        // mat.mat[0][0] = a2 + b2 - c2 - d2;
        // mat.mat[0][1] = 2.0 * (b * c + a * d);
        // mat.mat[0][2] = 2.0 * (b * d - a * c);
        // mat.mat[0][3] = 0.0;

        // mat.mat[1][0] = 2 * (b * c - a * d);
        // mat.mat[1][1] = a2 - b2 + c2 - d2;
        // mat.mat[1][2] = 2.0 * (c * d + a * b);
        // mat.mat[1][3] = 0.0;

        // mat.mat[2][0] = 2.0 * (b * d + a * c);
        // mat.mat[2][1] = 2.0 * (c * d - a * b);
        // mat.mat[2][2] = a2 - b2 - c2 + d2;
        // mat.mat[2][3] = 0.0;

        // mat.mat[3][0] = 0.0;
        // mat.mat[3][1] = 0.0;
        // mat.mat[3][2] = 0.0;
        // mat.mat[3][3] = 1.0;
        mat.mat[0] = a2 + b2 - c2 - d2;
        mat.mat[1] = 2.0 * (b * c + a * d);
        mat.mat[2] = 2.0 * (b * d - a * c);
        mat.mat[3] = 0.0;

        mat.mat[4] = 2 * (b * c - a * d);
        mat.mat[5] = a2 - b2 + c2 - d2;
        mat.mat[6] = 2.0 * (c * d + a * b);
        mat.mat[7] = 0.0;

        mat.mat[8] = 2.0 * (b * d + a * c);
        mat.mat[9] = 2.0 * (c * d - a * b);
        mat.mat[10] = a2 - b2 - c2 + d2;
        mat.mat[11] = 0.0;

        mat.mat[12] = 0.0;
        mat.mat[13] = 0.0;
        mat.mat[14] = 0.0;
        mat.mat[15] = 1.0;

        return Matrix4.transpose(mat);
    }
};
