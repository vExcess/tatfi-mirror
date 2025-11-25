const std = @import("std");

pub fn build(b: *std.Build) void {
    const mod = b.addModule("tetfy", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    const options = add_config(b, mod, &.{
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

    // In the `gvar` table it is impossibe to avoid allocations. This determines the
    // amount of variable tuples allocated on the stack. 32 is enough for most fonts
    // (which use 10-20 tuples), although the spec allows up to 4095.
    //
    // Functions going that route take an allocator parameter.
    const gvar = b.option(u7, "gvar_max_stack_tuples_len",
        \\Amount of stack allocation for the gvar table's variation tuples, before spilling to heap.
        \\Most fonts are in the 10-20 range.
    ) orelse 32;
    options.addOption(usize, "gvar_max_stack_tuples_len", gvar);

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
