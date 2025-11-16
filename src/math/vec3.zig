pub const Vec3 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return Vec3{
            .x = a.x + b.x,
            .y = a.y + b.y,
            .z = a.z + b.z,
        };
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return Vec3{
            .x = a.x - b.x,
            .y = a.y - b.y,
            .z = a.z - b.z,
        };
    }

    pub fn multf(a: Vec3, s: f32) Vec3 {
        return Vec3{
            .x = a.x * s,
            .y = a.y * s,
            .z = a.z * s,
        };
    }

    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return Vec3{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub fn getLength(a: Vec3) f32 {
        return @sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    }

    pub fn normalize(a: Vec3) Vec3 {
        var out: Vec3 = Vec3{};

        const len: f32 = a.getLength();
        if (len > 0) {
            const inv: f32 = 1.0 / len;
            out.x = a.x * inv;
            out.y = a.y * inv;
            out.z = a.z * inv;
        }

        return out;
    }

    pub fn ndlToRaster(a: Vec3, width: f32, height: f32) Vec3 {
        var out_vec = Vec3{};
        out_vec.x = (a.x + 1.0) * width * 0.5;
        out_vec.y = (1.0 - a.y) * 0.5 * height;
        out_vec.z = 1.0 / a.z;
        return out_vec;
    }
};
