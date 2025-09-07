//! The Flat  Queue is a minimal interface for a buffer backed queue. It supports push back
//! and pop front and will maintain items from front to back even after popping from the front.
//! However, this means that elements may not be stored in one contiguous slice and that the
//! first element may not be stored at index 0 of the underlying buffer.
const std = @import("std");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;
const check = std.testing;

const start_cap = 8;

pub fn FlatQueue(comptime T: type, comptime alignment: ?Alignment) type {
    if (alignment) |a| {
        if (a.toByteUnits() == @alignOf(T)) {
            return FlatQueue(T, null);
        }
    }
    return struct {
        const Self = @This();
        const Slice = if (alignment) |a| ([]align(a.toByteUnits()) T) else []T;
        items: Slice = &[_]T{},
        capacity: usize = 0,
        front: usize = 0,

        pub const empty: Self = .{
            .items = &.{},
            .front = 0,
        };

        pub fn deinit(
            self: *Self,
            gpa: Allocator,
        ) void {
            if (self.capacity != 0) {
                gpa.free(self.allocatedSlice());
            }
            self.* = Self.empty;
        }

        pub fn reserve(
            self: *Self,
            gpa: Allocator,
            to_add: usize,
        ) Allocator.Error!void {
            const need = self.items.len + to_add;
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
            if (self.items.len == self.capacity) {
                const newcap = if (self.capacity != 0) self.capacity * 2 else start_cap;
                try self.growAssumeGreater(gpa, newcap);
            }
            self.items.ptr[self.nextBackSlotAssumeCapacity()] = item;
            self.items.len += 1;
        }

        pub fn popFirst(self: *Self) ?T {
            if (self.items.len == 0) {
                return null;
            }
            const ret = self.items.ptr[self.front];
            self.front = (self.front + 1) % self.capacity;
            self.items.len -= 1;
            return ret;
        }

        pub fn first(self: *const Self) ?*T {
            return if (self.items.len == 0)
                null
            else
                &self.items.ptr[self.front];
        }

        pub fn len(self: *const Self) usize {
            return self.items.len;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.items.len == 0;
        }

        fn nextBackSlotAssumeCapacity(self: *const Self) usize {
            return (self.front + self.items.len) % self.capacity;
        }

        fn growAssumeGreater(
            self: *Self,
            gpa: Allocator,
            greater: usize,
        ) Allocator.Error!void {
            const new_mem = try gpa.alignedAlloc(T, alignment, greater);
            if (self.capacity != 0) {
                const old_mem = self.allocatedSlice();
                const first_chunk = @min(self.items.len, self.capacity - self.front);
                @memcpy(
                    new_mem[0..first_chunk],
                    self.items[self.front..(self.front + first_chunk)],
                );
                const second_chunk = self.items.len - first_chunk;
                if (second_chunk != 0) {
                    @memcpy(
                        new_mem[first_chunk..(first_chunk + second_chunk)],
                        self.items[0..second_chunk],
                    );
                }
                gpa.free(old_mem);
            }
            self.items.ptr = new_mem.ptr;
            self.capacity = new_mem.len;
            self.front = 0;
        }

        fn allocatedSlice(self: *const Self) Slice {
            return self.items.ptr[0..self.capacity];
        }
    };
}

test "construct" {
    const q = FlatQueue(u32, null).empty;
    try check.expect(q.front == 0 and q.items.len == 0 and q.capacity == 0);
}

test "init deinit empty" {
    var alloc = std.heap.DebugAllocator(.{}){};
    const gpa = alloc.allocator();
    var q = FlatQueue(u32, null).empty;
    defer q.deinit(gpa);
}

test "init deinit one resize" {
    var alloc = std.heap.DebugAllocator(.{}){};
    const gpa = alloc.allocator();
    var q = FlatQueue(u32, null).empty;
    defer q.deinit(gpa);
    try q.append(gpa, 19);
}

test "init deinit two resizes" {
    var alloc = std.heap.DebugAllocator(.{}){};
    const gpa = alloc.allocator();
    var q = FlatQueue(usize, null).empty;
    defer q.deinit(gpa);
    for (0..start_cap + 1) |i| {
        try q.append(gpa, i);
    }
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
