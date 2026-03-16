const std = @import("std");
const rasterizer = @import("renderer/rasterizer.zig");

const warmup = 5;
const samples = 10;
const outlier_threshold = 2;

test "Junk Shop" {
    var raw_timings: [samples]i128 = undefined;
    // var min_time: i128 = 0;
    // var max_time: i128 = 0;
    // var mean: i128 = 0;
    // var median: i128 = 0;
    // var std_dev: i128 = 0;
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    // if (!interactive) {
    rasterizer.init("/Users/urjasvisuthar/ZigCPURasterizer/assets/tavern/Untitled.gltf") catch |err| {
        // rasterizer.init("/Users/urjasvisuthar/ZigCPURasterizer/assets/junkshop_temp/thejunkshopsplashscreen-2.gltf") catch |err| {
        // rasterizer.init("/Users/urjasvisuthar/ZigCPURasterizer/assets/bistro/Untitled.gltf") catch |err| {
        std.debug.print("Error initializing the rasterizer: {any}\n", .{err});
    };
    defer rasterizer.deinit();

    std.debug.print("Starting warmup ({d} runs)...\n", .{warmup});
    for (0..warmup) |_| {
        try rasterizer.render(0, 0);
    }

    std.debug.print("Measuring {d} samples...\n", .{samples});
    for (0..rasterizer.scene.cameras.items.len) |idx| {
        for (0..samples) |sample| {
            const start = std.time.nanoTimestamp();
            try rasterizer.render(0, idx);
            const end = std.time.nanoTimestamp();
            raw_timings[sample] = end - start;
            // sum += end - start;
        }

        std.mem.sort(i128, &raw_timings, {}, std.sort.asc(i128));
        const raw_median = raw_timings[samples / 2];
        // std.debug.print("Time: {d} ns\n", .{end - start});

        var filtered_list: std.ArrayList(i128) = .empty;
        defer filtered_list.deinit(std.heap.page_allocator);

        for (raw_timings) |t| {
            if (t <= raw_median * outlier_threshold) {
                try filtered_list.append(std.heap.page_allocator, t);
            }
        }

        const timings = filtered_list.items;
        const count = timings.len;

        const min_time = timings[0];
        const max_time = timings[count - 1];
        var sum: i128 = 0;
        for (timings) |t| sum += t;
        const mean = @divFloor(sum, count);
        // const mean = sum / @as(f64, @floatFromInt(samples));

        // const median = if (samples % 2 == 0)
        // @divFloor(timings[samples / 2 - 1] + timings[samples / 2], 2)
        // else
        // timings[samples / 2];

        const p50_idx = count / 2;
        const p95_idx = @as(usize, @intFromFloat(@as(f64, @floatFromInt(count)) * 0.95)) - 1;
        const p99_idx = @as(usize, @intFromFloat(@as(f64, @floatFromInt(count)) * 0.99)) - 1;

        var variance_sum: i128 = 0;
        for (timings) |t| {
            variance_sum += std.math.pow(i128, t - mean, 2);
        }
        const std_dev = std.math.sqrt(@as(f64, @floatFromInt(@divFloor(variance_sum, count))));
        const coeff_variation = (std_dev / @as(f64, @floatFromInt(mean))) * 100.0;
        // const std_dev = std.math.sqrt(variance_sum / @as(f64, @floatFromInt(samples)));

        std.debug.print("\n--- Performance Results (nanoseconds) ---\n", .{});
        std.debug.print("{s:<15}: {d:>10.2} ns | {d:>10.4} ms\n", .{ "Min", min_time, @divFloor(min_time, std.time.ns_per_ms) });
        std.debug.print("{s:<15}: {d:>10.2} ns | {d:>10.4} ms\n", .{ "Max", max_time, @divFloor(max_time, std.time.ns_per_ms) });
        std.debug.print("{s:<15}: {d:>10.2} ns | {d:>10.4} ms\n", .{ "Mean", mean, @divFloor(mean, std.time.ns_per_ms) });
        std.debug.print("{s:<15}: {d:>10.2} ns | {d:>10.4} ms\n", .{ "Median (P50)", timings[p50_idx], @divFloor(timings[p50_idx], std.time.ns_per_ms) });
        std.debug.print("{s:<15}: {d:>10.2} ns | {d:>10.4} ms\n", .{ "Median (P95)", timings[p95_idx], @divFloor(timings[p95_idx], std.time.ns_per_ms) });
        std.debug.print("{s:<15}: {d:>10.2} ns | {d:>10.4} ms\n", .{ "Median (P99)", timings[p99_idx], @divFloor(timings[p99_idx], std.time.ns_per_ms) });
        std.debug.print("-----------------------\n", .{});
        std.debug.print("{s:<15}: {d:>10.2} ns | {d:>10.4} ms\n", .{ "Std Dev", std_dev, @divFloor(std_dev, std.time.ns_per_ms) });
        std.debug.print("{s:<15}: {d:>10.2} %\n", .{ "Coef. Var (CV)", coeff_variation });
        std.debug.print("-----------------------\n", .{});
        for (0..count) |sample_idx| {
            std.debug.print("{d:<15}: {d:>10.2} ns | {d:>10.4} ms\n", .{ sample_idx, timings[sample_idx], @divFloor(timings[sample_idx], std.time.ns_per_ms) });
        }
        if (timings.len < samples) {
            std.debug.print("Warning: Discarded {d} outliers!\n", .{samples - timings.len});
        }
        std.debug.print("-----------------------------------------\n", .{});
    }
    // }
}
