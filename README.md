# Molecule

Molecule is a Jai tower-wars game with a deterministic game core. Hosts collect
external events into `Frame_Input`, call the game once per simulation tick, and
own presentation and all I/O through `Platform`.

Build from this directory:

```powershell
jai Build.jai - win32
jai Build.jai - wasm
```

The Win32 bootstrap is deliberately headless until the native WebGPU/window
backend is selected. The browser bootstrap owns a canvas and schedules frames;
it writes the complete input record into WASM before calling `wasm_frame`.

The reference project remains in `IceEscapeReference/` and is intentionally not
part of either build.
