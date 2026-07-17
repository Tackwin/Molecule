# Molecule

Molecule is a Jai tower-wars game with a deterministic game core. Hosts collect
external events into `Frame_Input`, call the game once per simulation tick, and
own presentation and all I/O through `Platform`.

Build from this directory:

```powershell
jai Build.jai - win32
jai Build.jai - wasm
```

The Win32 bootstrap opens an SDL window; native WebGPU presentation is the next
backend step. The browser bootstrap owns a canvas and schedules frames; it
passes platform-collected frame data through a narrow WASM ABI before calling
`wasm_frame`.

The browser WebGPU bridge uses JSPI: JavaScript is restricted to passing WebGPU
calls through to the browser, while Jai owns renderer setup and draw commands.

To serve the browser build locally, run `python web/server.py` and open
`http://localhost:8000/`.

The reference project remains in `IceEscapeReference/` and is intentionally not
part of either build.
