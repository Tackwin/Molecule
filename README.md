# Molecule

Molecule is a Jai tower-wars game with a deterministic game core. Hosts collect
external events into `Frame_Input`, call the game once per simulation tick, and
own presentation and all I/O through `Platform`.

Build from this directory:

```powershell
jai Build.jai - win32
jai Build.jai - wasm
jai Build.jai - qoi-test
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

## Win32 control pipe and capture

The Win32 game creates a local named pipe at `\\.\pipe\MoleculeControl`. Use
the supplied PowerShell helper from the repository root while the game runs:

```powershell
./tools/molecule_control.ps1 mouse 640 360
./tools/molecule_control.ps1 mouse_delta 12 -6
./tools/molecule_control.ps1 key z down
./tools/molecule_control.ps1 key z up
./tools/molecule_control.ps1 pause
./tools/molecule_control.ps1 resume
./tools/molecule_control.ps1 capture start
./tools/molecule_control.ps1 capture stop
./tools/molecule_control.ps1 quit
```

`capture start` writes consecutive QOI images into `build/captures/`. The capture
uses the presented Win32 client area, so keep the game window visible and
unobscured while recording. Convert the sequence with FFmpeg, for example:

```powershell
ffmpeg -framerate 60 -i build/captures/frame_%d.qoi -c:v libx264 -pix_fmt yuv420p molecule.mp4
```
