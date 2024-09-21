const std = @import("std");

pub const Vec2 = packed struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub inline fn extend(self: Vec2, z: f32) Vec3 {
        return .{
            .x = self.x,
            .y = self.y,
            .z = z,
        };
    }
};

pub const Vec3 = packed struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub inline fn extend(self: Vec3, w: f32) Vec4 {
        return .{ .x = self.x, .y = self.y, .z = self.z, .w = w };
    }

    pub inline fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }
};

pub const Vec4 = packed struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 0.0,

    pub fn eq(self: Vec4, other: Vec4) bool {
        return self.x == other.x and self.y == other.y and self.z == other.z and self.w == other.w;
    }

    pub inline fn add(self: Vec4, other: Vec4) Vec4 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
            .w = self.w + other.w,
        };
    }

    pub inline fn dot(self: Vec4, other: Vec4) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
    }
};

pub const Mat4 = packed struct {
    i: Vec4 = .{},
    j: Vec4 = .{},
    k: Vec4 = .{},
    t: Vec4 = .{},

    pub const IDENDITY = Mat4{
        .i = Vec4{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 },
        .j = Vec4{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 },
        .k = Vec4{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 },
        .t = Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 },
    };

    pub fn eq(self: Mat4, other: Mat4) bool {
        return self.i.eq(other.i) and self.j.eq(other.j) and self.k.eq(other.k) and self.t.eq(other.t);
    }

    pub inline fn translate(self: Mat4, v: Vec3) Mat4 {
        var tmp = self;
        tmp.t = tmp.t.add(v.extend(0));
        return tmp;
    }

    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / @tan(fovy / 2.0);
        return .{
            .i = .{ .x = f / aspect },
            .j = .{ .y = f },
            .k = .{ .z = far / (near - far), .w = -1.0 },
            .t = .{ .z = -(far * near) / (far - near), .w = 0.0 },
        };
    }

    pub fn mul(self: Mat4, other: Mat4) Mat4 {
        return .{
            .i = .{
                .x = self.i.x * other.i.x + self.i.y * other.j.x + self.i.z * other.k.x + self.i.w * other.t.x,
                .y = self.i.x * other.i.y + self.i.y * other.j.y + self.i.z * other.k.y + self.i.w * other.t.y,
                .z = self.i.x * other.i.z + self.i.y * other.j.z + self.i.z * other.k.z + self.i.w * other.t.z,
                .w = self.i.x * other.i.w + self.i.y * other.j.w + self.i.z * other.k.w + self.i.w * other.t.w,
            },
            .j = .{
                .x = self.j.x * other.i.x + self.j.y * other.j.x + self.j.z * other.k.x + self.j.w * other.t.x,
                .y = self.j.x * other.i.y + self.j.y * other.j.y + self.j.z * other.k.y + self.j.w * other.t.y,
                .z = self.j.x * other.i.z + self.j.y * other.j.z + self.j.z * other.k.z + self.j.w * other.t.z,
                .w = self.j.x * other.i.w + self.j.y * other.j.w + self.j.z * other.k.w + self.j.w * other.t.w,
            },
            .k = .{
                .x = self.k.x * other.i.x + self.k.y * other.j.x + self.k.z * other.k.x + self.k.w * other.t.x,
                .y = self.k.x * other.i.y + self.k.y * other.j.y + self.k.z * other.k.y + self.k.w * other.t.y,
                .z = self.k.x * other.i.z + self.k.y * other.j.z + self.k.z * other.k.z + self.k.w * other.t.z,
                .w = self.k.x * other.i.w + self.k.y * other.j.w + self.k.z * other.k.w + self.k.w * other.t.w,
            },
            .t = .{
                .x = self.t.x * other.i.x + self.t.y * other.j.x + self.t.z * other.k.x + self.t.w * other.t.x,
                .y = self.t.x * other.i.y + self.t.y * other.j.y + self.t.z * other.k.y + self.t.w * other.t.y,
                .z = self.t.x * other.i.z + self.t.y * other.j.z + self.t.z * other.k.z + self.t.w * other.t.z,
                .w = self.t.x * other.i.w + self.t.y * other.j.w + self.t.z * other.k.w + self.t.w * other.t.w,
            },
        };
    }
};

test "mat4_mul" {
    {
        const mat_1 = Mat4.IDENDITY;
        const mat_2 = Mat4.IDENDITY;
        const m = mat_1.mul(mat_2);
        std.debug.assert(m.eq(Mat4.IDENDITY));
    }

    {
        const mat_1 = Mat4{
            .i = .{ .x = 1.0, .y = 2.0, .z = 3.0, .w = 4.0 },
            .j = .{ .x = 5.0, .y = 6.0, .z = 7.0, .w = 8.0 },
            .k = .{ .x = 9.0, .y = 10.0, .z = 11.0, .w = 12.0 },
            .t = .{ .x = 13.0, .y = 14.0, .z = 15.0, .w = 16.0 },
        };
        const mat_2 = Mat4{
            .i = .{ .x = 17.0, .y = 18.0, .z = 19.0, .w = 20.0 },
            .j = .{ .x = 21.0, .y = 22.0, .z = 23.0, .w = 24.0 },
            .k = .{ .x = 25.0, .y = 26.0, .z = 27.0, .w = 28.0 },
            .t = .{ .x = 29.0, .y = 30.0, .z = 31.0, .w = 32.0 },
        };
        const m = mat_1.mul(mat_2);
        const expected = .{
            .i = .{ .x = 250.0, .y = 260.0, .z = 270.0, .w = 280.0 },
            .j = .{ .x = 618.0, .y = 644.0, .z = 670.0, .w = 696.0 },
            .k = .{ .x = 986.0, .y = 1028.0, .z = 1070.0, .w = 1112.0 },
            .t = .{ .x = 1354.0, .y = 1412.0, .z = 1470.0, .w = 1528.0 },
        };
        std.debug.assert(m.eq(expected));
    }
}
