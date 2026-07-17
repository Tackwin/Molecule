#import "Compiler";
#import "Basic";
#import "String";

configure_common :: (workspace: Workspace) {
    options := get_build_options(workspace);
    options.output_path = "./build/";

    paths: [..] string;
    paths.allocator = temp;
    array_add(*paths, "./src/");
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

build_win32 :: () {
    workspace := compiler_create_workspace("Molecule Win32");
    configure_common(workspace);
    options := get_build_options(workspace);
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "Molecule";
    set_build_options(options, workspace);
    compile_workspace(workspace, "src/entry/win32.jai");
}

build_wasm :: () {
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
}

build :: () {
    set_build_options_dc(.{ do_output = false });
    args := get_build_options().compile_time_command_line;
    wants_win32 := false;
    wants_wasm := false;
    for args {
        wants_win32 |= compare(it, "win32") == 0;
        wants_wasm |= compare(it, "wasm") == 0;
    }
    if !wants_win32 && !wants_wasm wants_win32 = true;
    if wants_win32 build_win32();
    if wants_wasm build_wasm();
}

#run build();
