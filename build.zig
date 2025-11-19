const std = @import("std");

pub fn build(b: *std.Build) void {
    const mod = b.addModule("tetfy", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    _ = add_config(b, mod, &.{
        .{
            .name = "variable_fonts",
            .desc =
            \\Enables variable fonts support. Increases binary size.
            \\Includes avar, CFF2, fvar, gvar, HVAR, MVAR and VVAR tables
            ,
        },
        .{
            .name = "opentype_layout",
            .desc = "Enables GDEF, GPOS, GSUB and MATH tables",
        },
        .{
            .name = "apple_layout",
            .desc = "Enables ankr, feat, format1 subtable in kern, kerx, morx and trak tables",
        },
    });

    if (b.pkg_hash.len == 0)
        set_up_testing_exe(b, mod);
}

fn add_config(
    b: *std.Build,
    mod: *std.Build.Module,
    cfgs: []const struct { name: []const u8, desc: []const u8 },
) *std.Build.Step.Options {
    const options = b.addOptions();
    mod.addOptions("config", options);

    for (cfgs) |cfg| {
        const c = b.option(bool, cfg.name, cfg.desc) orelse true;
        options.addOption(bool, cfg.name, c);
    }

    // in case we need to add non-bool options
    return options;
}

fn set_up_testing_exe(
    b: *std.Build,
    mod: *std.Build.Module,
) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "foo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),

            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "tetfy", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
}
