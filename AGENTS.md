# Molecule Agent Guide

This file records the durable engineering decisions and working preferences for this repository. Follow it before making changes. When current code and this document disagree, inspect the history and ask before changing an architectural invariant.

## Project intent

Molecule is a data-oriented tower-wars game inspired by Warcraft 3 Line Tower Wars. It is written in Jai and targets both a Win32 executable and the browser through WASM/WebGPU.

The long-term requirements are:

- deterministic simulation from recorded inputs;
- input replay;
- headless execution;
- a future MCP-like control/debug API for AI agents;
- native Win32 and browser builds sharing the same game code.

Keep these requirements in mind even when implementing a small feature. Do not introduce hidden time, OS, random, or I/O dependencies into game logic.

## Reference project

`IceEscapeReference/` is the author's older Jai game and is the primary reference for established patterns, especially rendering, platform abstraction, context remapping, Store code, OBJ parsing, and WebGPU bindings.

- Consult it when implementing related systems instead of inventing an unrelated architecture.
- It is read-only reference material for this project.
- Never include `IceEscapeReference/` in Molecule commits or builds.
- The reference's `bin/` and `lib/` contain the native WebGPU dependencies used by the Win32 build.

## Communication and working style

- Ask when an architectural choice is genuinely ambiguous. The author prefers a short question over a large speculative implementation.
- Once the direction is clear, finish the whole requested slice before handing it back.
- Never claim a feature works based only on code inspection. Build it, run it, and test the relevant behavior.
- For visual changes, take and inspect a screenshot. Compilation and a clean console are not sufficient.
- Debug logging is welcome, especially at platform boundaries, asset promotion, and WebGPU failure paths.
- Do not commit unless explicitly asked. When asked to commit, exclude unrelated files and `IceEscapeReference/`.
- Do not touch or stage `tools/Super.QOI.converter.GUI.exe`; it is a user-owned untracked tool.
- Preserve unrelated dirty-worktree changes.

## Jai style

- Use one statement per line. Do not compress several statements onto one line.
- Jai supports operator overloading. Use `+`, `-`, `*`, and `/` for algebra instead of helpers such as `m4_multiply`.
- Jai supports function overloading. Prefer names such as `dot`, not names prefixed with the argument type such as `v2f_dot`.
- Use locally scoped functions and types when helpers only belong to one procedure. Jai local functions are not closures; do not treat them as closures.
- Use standard modules and functions when appropriate. Do not reimplement basic math such as square root without a concrete reason.
- Prefer `scan2` for straightforward text formats such as OBJ and CSV. Keep parsers small and test them with the real bundled assets.
- Use `Table` from `Hash_Table` for lookup/topology work instead of avoidable quadratic scans.
- Use the temporary allocator for scratch arrays and tables: `.allocator = temp`.
- Use `Pool.jai` for persistent Store-owned asset memory.
- Prefer explicit, readable code over minification or clever compression, including WGSL.
- Write capacity/byte-size magic constants in hexadecimal when that makes their storage meaning clearer, for example `0x01000000` rather than `16777216`.

## Algebra and coordinate conventions

All math and linear-algebra data types and their pure operations belong in `src/Algebra.jai`.

- Keep `Algebra.jai` free of imports up to reasonable necessities such as the standard Math module.
- It should contain pure data types and operations on those types, not game or platform behavior.
- Use operator overloads there.
- The gameplay plane is **XY**.
- **Z is elevation/render depth**, with positive Z above/in front of the gameplay plane.
- Matrices use column vectors and column-major storage.
- Keep view, projection, transforms, shader multiplication order, and CPU/GPU layouts consistent with that convention.

## Platform architecture

The game may access the host only through `Platform` in `src/platform.jai`.

- `Platform.system` contains ordinary host services.
- `Platform.gpu` contains the WebGPU function table.
- WebGPU entries must use WebGPU C API names such as `wgpuDeviceCreateBuffer`; do not invent wrapper names that make a known WebGPU call hard to identify.
- Win32 fills the table with calls into `wgpu_native.dll`.
- WASM fills the same table with JavaScript passthrough imports.
- JavaScript is a thin platform bridge. Renderer creation, WebGPU resource management, pipelines, and draw submission belong in Jai.
- Browser suspension uses **JSPI exclusively**. Do not add Asyncify.
- Log every rejected pointer/descriptor and null/undefined early return in `web/webgpu_passthrough.js`; silent bridge failures are expensive to diagnose.

The game is pure in spirit: each tick depends on persistent game state plus `Frame_Input`, and emits rendering/platform requests through `Platform`.

### Frame input

- Do not add an input tick index. Simulation should not depend on an externally supplied tick number.
- The platform owns a frame arena, resets it each frame, and allocates all variable-sized `Frame_Input` payloads from it.
- The game may not retain pointers into the frame arena after the tick.
- A recorder copies the arena contents and serializes slice offsets with the fixed input data.
- Keep `capture_frame` a boolean. The platform owns start/stop capture state.
- On WASM, JavaScript writes input directly into one preallocated structured buffer installed at boot, then calls `wasm_frame`. Do not reintroduce per-field boundary calls such as `wasm_set_move_key` or `set_frame_basics`.
- Movement bindings are **ZQSD** plus arrow keys, not WASD. F8 toggles the GUI demo.

## Determinism and timing

- The platform supplies `simulation_delta_seconds`.
- Simulation must be reproducible from the initial seed and recorded `Frame_Input` sequence.
- Avoid reading wall-clock time, polling input, opening files, or generating nondeterministic randomness from game code.
- Keep presentation/capture concerns from changing simulation results.
- Prefer fixed-step tests through the Win32 control pipe when validating gameplay sequences.

## Game/DLL hot reload

Win32 uses a reloadable game DLL. Persistent game state, resizable arrays, Store pools, and GPU resources are intended to survive a reload.

The dangerous part is allocator function pointers: Jai's `#Context` default allocator may be copied into a resizable array on its first allocation. The launcher must remap the game context so persistent allocators point to launcher-owned code rather than an unloaded DLL. Follow `src/entry/game_win32.jai`, `Remap_Context`, and the reference project's `main_game.jai`.

- Do not free persistent arrays, pools, or GPU resources merely because the DLL reloads.
- Do not store allocator procedures that point into the reloadable DLL.
- Refresh code/function pointers that genuinely originate in the reloaded DLL.
- Final shutdown and hot reload are different operations; do not conflate them.

## Renderer architecture

The renderer follows the “No Graphics API”/reference `WRender` philosophy:

- a small fixed set of shaders;
- simple, uniform vertex formats;
- vertex pulling from storage buffers;
- one CPU instance buffer for the frame;
- a small, stable texture set;
- minimal abstractions over WebGPU.

The game side decides when rendering occurs. The platform only provides WebGPU calls and presents the surface chosen by the host.

- `renderer_render_game` consumes the game state and owns the logic that turns game objects into renderer instances. Game code should not manually call special-purpose `renderer_push_cube`/`renderer_push_sphere` helpers.
- The Store pushes promoted assets to the renderer for GPU upload. The renderer writes GPU offsets/counts back into the asset. The renderer should not pull arbitrary Store internals.
- Mesh GPU offsets/counts belong in `Mesh_Asset`, not in an unrelated renderer lookup table.
- All OBJ geometry is triangles. Do not add quad-face support.
- Meshes have per-vertex UVs.
- Most textured instances use `Assets/textures/palette.qoi`, reserved in the first geometry bind group. Instance flags determine whether palette texturing is enabled.
- Do not add a PNG decoder. A QOI palette asset exists even if a source PNG is also present.
- The forward pass uses 4x MSAA.
- The current object-space cavity/highlight system uses one `Mesh_Triangle` record per triangle with a face normal and three signed neighbor-edge values. The shader evaluates all three nearby edges and takes the strongest contribution so coplanar diagonals cannot suppress perpendicular cube edges.
- Keep screen-space derivative antialiasing and projected-width/distance fading in mind when changing cavity rendering; distant subpixel lines otherwise shimmer badly.

Frame capture is split deliberately:

- the renderer's job is to copy presented RGBA pixels into caller-provided memory;
- the game/caller decides whether to encode QOI and which path to write;
- the platform owns capture start/stop policy.

## Assets and Store

`Build.jai` bundles every file found recursively under `Assets/` into one binary blob.

- The blob supports an asset entry containing multiple paths. Files with the same logical stem, such as `verdana.csv` and `verdana.qoi`, are paired into one asset group.
- Do not generate a `Store_Generated.jai` file. Named Store fields are handwritten so disk changes never silently materialize as source changes.
- For now all runtime assets are known ahead of time and have named fields in `Store`.
- Promote raw `Store_Asset` data immediately into typed resources such as `Shader_Asset`, `Mesh_Asset`, `Texture_Asset`, `Font_Asset`, or future MP3 audio resources.
- Do not pass an asset blob as a special argument to game initialization. The Store obtains it through the normal Platform channel, using `try_get_asset_blob` for an immediate synchronous mapping when the host has one.
- Pass the Store itself to renderer initialization rather than threading individual shader assets through its signature.
- A font is one logical asset composed from metrics and atlas paths. Promote the CSV as font metrics and the QOI as a texture; do not call the same incorrect promotion path for both.
- The platform-provided raw bytes are transient. Copy anything that must survive the frame into Store-owned Pool memory.
- Win32 first resolves assets immediately from its memory-mapped blob and can fall back to raw-file asynchronous loading.
- WASM may dispatch independent GET requests and promote assets as they arrive while the game continues running.
- Async slots have explicit `EMPTY`, `PENDING`, `READY`, and `FAILED` states. Allocate only an `EMPTY` slot; never overwrite a finished-but-not-taken request. Reset a slot to `EMPTY` after `asset_take` closes it.
- Shader file watching is a platform service. The Store requests changed shaders and the renderer reconstructs the affected pipeline while preserving the old working pipeline if rebuild fails.
- Use temporary arrays/tables for parsing and topology construction, and Store pools only for the promoted persistent result.

Supported asset conventions:

- meshes: triangle-only OBJ;
- textures: QOI;
- audio: MP3 when audio is introduced;
- shaders: WGSL.

## GUI conventions

- GUI layout is a stack/state machine controlled by calls such as `gui_push_row`, `gui_push_column`, and `gui_pop_layout`.
- A pushed layout saves its starting cursor and accumulates the complete child AABB. Popping restores the parent cursor and advances it by the completed row/column bounds.
- Keep two GUI pools: one reset every frame for temporary data and one persistent pool for widget state/maps.
- Route all GUI allocations through the appropriate pool.
- Text is internally split into `prepare_text` and `place_prepared_text`.
- Preparation returns at least text size and may include per-character offsets for caret/hit testing, allowing callers to make placement decisions before emitting quads.
- F8 must continue to expose a working demo screen covering widgets and nested layouts.

## Testing requirements

Testing is part of implementation, not an optional handoff suggestion. Run tests proportional to the change, and test both platforms for shared game/renderer/Store changes.

### Build checks

From the repository root:

```powershell
jai Build.jai - win32
jai Build.jai - wasm
```

Use `git diff --check` before handoff. Do not recreate the removed auxiliary `build_store_blob_test` or `build_qoi_test` targets; test through the real builds and runtime assets.

### WASM/WebGPU runtime check

Start the local server from the repository root:

```powershell
python web/server.py
```

Then, in another process:

```powershell
node .\tools\web_runtime_check.cjs http://localhost:8000/
```

The harness launches full headless Chromium with SwiftShader WebGPU, waits for initialization and multiple frames, reports console/page errors, and writes:

```text
web/runtime-check.png
```

Always inspect that image for visual work. If the feature needs input, use Playwright to send keyboard, mouse, wheel, or GUI interaction before taking the screenshot. Do not rely only on the default three-frame image. Stop the development server after the test.

Check browser logs for JavaScript exceptions and WebGPU validation errors, including attachment-size mismatches and passthrough null checks.

### Win32 deterministic control and capture

Launch `build/Molecule.exe` with `build/` as its working directory. In automated environments it may be launched hidden. The game exposes `\\.\pipe\MoleculeControl` through:

```powershell
.\tools\molecule_control.ps1 status
.\tools\molecule_control.ps1 pause
.\tools\molecule_control.ps1 resume
.\tools\molecule_control.ps1 step 1
.\tools\molecule_control.ps1 key z down
.\tools\molecule_control.ps1 key z up
.\tools\molecule_control.ps1 key f8 down
.\tools\molecule_control.ps1 key f8 up
.\tools\molecule_control.ps1 mouse 640 360
.\tools\molecule_control.ps1 mouse_delta 12 -6
.\tools\molecule_control.ps1 wheel 4
.\tools\molecule_control.ps1 capture once
.\tools\molecule_control.ps1 capture start
.\tools\molecule_control.ps1 capture stop
.\tools\molecule_control.ps1 quit
```

Captured QOI frames are written under `build/captures/`. `tools/capture_demo.ps1` demonstrates a deterministic paused/stepped input sequence and validates that all expected frames exist. The native capture uses the presented client area; for ordinary visible capture, keep the window unobscured.

Use these controls to reproduce input bugs, validate F8, movement, mouse interactions, zoom, frame capture, and deterministic sequences without asking the author to operate the game manually.

## Current gameplay conventions

- The board is a 40 by 15 grid on the XY plane.
- Camera movement supports ZQSD and arrows; the mouse wheel zooms with minimum/maximum target distance.
- Water/molecule waves travel across the board from right to left above the grid.
- Camera and gameplay changes must preserve the XY/Z convention and column-major, column-vector math.

These are current design facts, not permission to hard-code platform behavior into the simulation.
