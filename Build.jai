#import "Compiler";
#import "Basic";
#import "File_Utilities";
#import "File";
#import "String";

Asset_Blob_Header :: struct {
    magic: [8] u8;
    version: u32;
    asset_count: u32;
}

Asset_Blob_Entry :: struct {
    path_count: u32;
}

Asset_Blob_Path :: struct {
    path_bytes: u32;
    data_bytes: u32;
}

Asset_Blob_Group :: struct {
    stem: string;
    paths: [..] string;
}

asset_blob_stem :: (path: string) -> string {
    stem_end := path.count;
    for 0..path.count - 1 {
        if path.data[it] == #char "." {
            stem_end = it;
        }
    }
    return .{ data = path.data, count = stem_end };
}

build_assets_blob :: () {
    files := file_list("Assets", recursive = true);
    groups: [..] Asset_Blob_Group;
    groups.allocator = temp;
    for files {
        relative_path := advance(it, "Assets/".count);
        stem := asset_blob_stem(relative_path);
        group: *Asset_Blob_Group;
        for *candidate: groups {
            if candidate.stem == stem {
                group = candidate;
                break;
            }
        }
        if !group {
            array_add(*groups, .{ stem = stem });
            group = *groups[groups.count - 1];
            group.paths.allocator = temp;
        }
        array_add(*group.paths, relative_path);
    }

    output, success := file_open("build/assets.blob", for_writing = true, keep_existing_content = false);
    if !success return;
    defer file_close(*output);
    header: Asset_Blob_Header = .{};
    header.magic[0] = 77;
    header.magic[1] = 79;
    header.magic[2] = 76;
    header.magic[3] = 65;
    header.magic[4] = 83;
    header.magic[5] = 83;
    header.magic[6] = 69;
    header.magic[7] = 84;
    header.version = 2;
    header.asset_count = xx groups.count;
    file_write(*output, *header, size_of(Asset_Blob_Header));
    for groups {
        entry: Asset_Blob_Entry;
        entry.path_count = xx it.paths.count;
        file_write(*output, *entry, size_of(Asset_Blob_Entry));
        for it.paths {
            data, data_success := read_entire_file(tprint("Assets/%", it), log_errors = true);
            if !data_success return;
            path: Asset_Blob_Path;
            path.path_bytes = xx it.count;
            path.data_bytes = xx data.count;
            file_write(*output, *path, size_of(Asset_Blob_Path));
            file_write(*output, it.data, it.count);
            file_write(*output, data.data, data.count);
        }
    }
}

configure_common :: (workspace: Workspace) {
    seed := get_build_options();
    options := get_build_options(workspace);
    options.output_path = "./build/";
    options.Commonly_Propagated = seed.Commonly_Propagated;

    paths: [..] string;
    paths.allocator = temp;
    array_add(*paths, "./src/");
    array_add(*paths, "./JaiStd/modules/");
    array_add(*paths, ..options.import_path);
    options.import_path = paths;
    set_build_options(options, workspace);
}

compile_workspace :: (workspace: Workspace, entry_file: string) {
    compiler_begin_intercept(workspace);
    add_build_file(entry_file, workspace);
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE break;
    }
    compiler_end_intercept(workspace);
}

build_win32_game :: () {
    workspace := compiler_create_workspace("Molecule Win32 Game");
    configure_common(workspace);
    options := get_build_options(workspace);
    options.output_type = .DYNAMIC_LIBRARY;
    options.output_executable_name = "MoleculeGame";
    set_build_options(options, workspace);
    compile_workspace(workspace, "src/entry/game_win32.jai");
}

build_win32_launcher :: () {
    workspace := compiler_create_workspace("Molecule Win32 Launcher");
    configure_common(workspace);
    options := get_build_options(workspace);
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "Molecule";
    options.additional_linker_arguments = .[
        "IceEscapeReference/lib/wgpu_native.lib",
        "User32.lib",
        "Userenv.lib",
        "Ntdll.lib",
        "Propsys.lib",
        "OpenGL32.lib",
        "Ole32.lib",
        "Gdi32.lib",
        "OleAut32.lib",
        "d3dcompiler.lib",
        "RuntimeObject.lib",
        "Ws2_32.lib"
    ];
    set_build_options(options, workspace);
    compile_workspace(workspace, "src/entry/win32.jai");
    copy_file("IceEscapeReference/bin/wgpu_native.dll", "build/wgpu_native.dll");
    copy_file("IceEscapeReference/bin/SDL2.dll", "build/SDL2.dll");
}

build_win32 :: () {
    build_assets_blob();
    build_win32_game();
    build_win32_launcher();
}

build_wasm :: () {
    build_assets_blob();
    workspace := compiler_create_workspace("Molecule WASM");
    configure_common(workspace);
    options := get_build_options(workspace);
    options.output_type = .DYNAMIC_LIBRARY;
    options.output_executable_name = "molecule";
    options.output_path = "./web/";
    options.backend = .LLVM;
    options.os_target = .WASM;
    options.cpu_target = .CUSTOM;
    options.backtrace_on_crash = .OFF;
    options.llvm_options.target_system_features = "+bulk-memory,+atomics";
    options.llvm_options.function_sections = true;
    options.additional_linker_arguments = .[
        "--import-memory",
        "--shared-memory",
        "--export-memory",
        "--stack-first",
        "-z", "stack-size=1048576",
        "src/c/walloc.o"
    ];
    set_build_options(options, workspace);
    remap_import(workspace, "*", "Default_Allocator", "Walloc");
    compile_workspace(workspace, "src/entry/wasm.jai");
    copy_file("build/assets.blob", "web/assets.blob");
}

build :: () {
    set_build_options_dc(.{ do_output = false });
    args := get_build_options().compile_time_command_line;
    wants_win32 := false;
    wants_win32_game := false;
    wants_win32_launcher := false;
    wants_wasm := false;
    for args {
        wants_win32 |= compare(it, "win32") == 0;
        wants_win32_game |= compare(it, "win32-game") == 0;
        wants_win32_launcher |= compare(it, "win32-launcher") == 0;
        wants_wasm |= compare(it, "wasm") == 0;
    }
    if !wants_win32 && !wants_win32_game && !wants_win32_launcher && !wants_wasm {
        wants_win32 = true;
    }
    if wants_win32 {
        build_win32();
    } else if wants_win32_game || wants_win32_launcher {
        build_assets_blob();
        if wants_win32_game build_win32_game();
        if wants_win32_launcher build_win32_launcher();
    }
    if wants_wasm build_wasm();
}

#run build();
