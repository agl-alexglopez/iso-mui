//! The Flat  Queue is a minimal interface for a buffer backed queue. It supports push back
//! and pop front and will maintain items from front to back even after popping from the front.
//! However, this means that elements may not be stored in one contiguous slice and that the
//! first element may not be stored at index 0 of the underlying buffer.
const std = @import("std");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;
const check = std.testing;

pub fn FlatQueue(comptime T: type, comptime alignment: ?Alignment) type {
    return struct {
        const Self = @This();
        const Slice = if (alignment) |a| ([]align(a.toByteUnits()) T) else []T;
        buf: Slice,
        capacity: usize = 0,
        front: usize = 0,

        pub const empty: Self = .{
            .buf = &.{},
            .front = 0,
        };

        pub fn deinit(
            self: *Self,
            gpa: Allocator,
        ) void {
            gpa.free(self.buf);
            self.capacity = 0;
            self.front = 0;
            self.* = undefined;
        }

        pub fn reserve(
            self: *Self,
            gpa: Allocator,
            to_add: usize,
        ) Allocator.Error!void {
            const need = self.buf.len + to_add;
            if (self.capacity >= need) {
                return;
            }
            try self.growAssumeGreater(gpa, need);
        }

        pub fn append(
            self: *Self,
            gpa: Allocator,
            item: T,
        ) Allocator.Error!void {
            if (self.buf.len == self.capacity) {
                const newcap = if (self.capacity != 0) self.capacity * 2 else 8;
                try self.growAssumeGreater(gpa, newcap);
            }
            self.buf.ptr[self.nextBackSlotAssumeCapacity()] = item;
            self.buf.len += 1;
        }

        pub fn popFirst(self: *Self) ?T {
            if (self.buf.len == 0) {
                return null;
            }
            const ret = self.buf.ptr[self.front];
            self.front = (self.front + 1) % self.capacity;
            self.buf.len -= 1;
            return ret;
        }

        pub fn first(self: *const Self) ?*T {
            return if (self.buf.len == 0)
                null
            else
                &self.buf.ptr[self.front];
        }

        pub fn len(self: *const Self) usize {
            return self.buf.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.buf.len == 0;
        }

        fn nextBackSlotAssumeCapacity(self: *const Self) usize {
            return (self.front + self.buf.len) % self.capacity;
        }

        fn lastSlotAssumeCapacity(self: *const Self) usize {
            return (self.front + self.buf.len - 1) % self.capacity;
        }

        fn growAssumeGreater(
            self: *Self,
            gpa: Allocator,
            greater: usize,
        ) Allocator.Error!void {
            const old_len = self.buf.len;
            var new_mem: []T = try gpa.alloc(T, greater);
            if (self.capacity != 0) {
                const first_chunk = @min(self.buf.len, self.capacity - self.front);
                @memcpy(
                    new_mem.ptr,
                    self.buf.ptr[self.front..(self.front + first_chunk)],
                );
                if (first_chunk < self.capacity) {
                    @memcpy(
                        new_mem.ptr[first_chunk..],
                        self.buf.ptr[0..(self.buf.len - first_chunk)],
                    );
                }
            }
            self.capacity = greater;
            self.front = 0;
            gpa.free(self.buf);
            self.buf = new_mem;
            self.buf.len = old_len;
        }
    };
}

test "construct" {
    const q = FlatQueue(u32, null).empty;
    try check.expect(q.front == 0 and q.buf.len == 0 and q.capacity == 0);
}

test "append" {
    var b: [@sizeOf(u32) * 100]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&b);
    const gpa = alloc.allocator();
    var q = FlatQueue(u32, null).empty;
    try q.append(gpa, 32);
    try check.expectEqual(0, q.front);
    try check.expectEqual(1, q.len());
    try check.expect(q.first() != null);
    if (q.first()) |f| {
        try check.expectEqual(32, f.*);
    }
    try q.append(gpa, 33);
    try check.expectEqual(0, q.front);
    try check.expectEqual(2, q.len());
    try check.expect(q.first() != null);
    if (q.first()) |f| {
        try check.expectEqual(32, f.*);
    }
}
