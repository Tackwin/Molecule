const canvas = document.querySelector("#game");
let wasm;

function resizeCanvas() {
  const ratio = devicePixelRatio || 1;
  canvas.width = Math.floor(innerWidth * ratio);
  canvas.height = Math.floor(innerHeight * ratio);
}

async function boot() {
  resizeCanvas();
  addEventListener("resize", resizeCanvas);

  // Jai currently emits wasm64; its imported memory therefore uses 64-bit addresses.
  // Keep these limits in sync with the current linker output (18 64 KiB pages).
  // Imported shared memory must not declare a larger maximum than the WASM module.
  const memory = new WebAssembly.Memory({ initial: 18n, maximum: 18n, shared: true, address: "i64" });
  const imports = { env: new Proxy({ memory }, { get: (target, name) => target[name] ?? (() => 0) }) };
  const response = await fetch("molecule.wasm");
  const { instance } = await WebAssembly.instantiateStreaming(response, imports);
  wasm = instance.exports;
  wasm.wasm_init();
  requestAnimationFrame(frame);
}

function frame() {
  wasm.wasm_set_frame_basics(1 / 60, innerWidth, innerHeight, canvas.width, canvas.height);
  wasm.wasm_frame();
  requestAnimationFrame(frame);
}

boot().catch(error => { console.error(error); document.body.dataset.error = error.message; });
