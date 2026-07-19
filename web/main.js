const canvas = document.querySelector("#game");
let wasm;
let wasm_frame;
const movementKeyIndex = new Map([
  ["z", 0],
  ["ArrowUp", 0],
  ["q", 1],
  ["ArrowLeft", 1],
  ["s", 2],
  ["ArrowDown", 2],
  ["d", 3],
  ["ArrowRight", 3],
  ["f8", 4],
]);
const movementDown = new Uint8Array(5);
const movementPressed = new Uint8Array(5);
const movementReleased = new Uint8Array(5);
let mouseX = 0;
let mouseY = 0;
let mouseButtonsDown = 0;
let mouseButtonsPressed = 0;
let mouseButtonsReleased = 0;

function resizeCanvas() {
  const ratio = devicePixelRatio || 1;
  canvas.width = Math.floor(innerWidth * ratio);
  canvas.height = Math.floor(innerHeight * ratio);
}

function movementKeyForEvent(event) {
  if (event.key.startsWith("Arrow")) {
    return event.key;
  }
  return event.key.toLowerCase();
}

async function boot() {
  if (!navigator.gpu) throw new Error("This browser does not expose WebGPU.");
  resizeCanvas();
  addEventListener("resize", resizeCanvas);
  addEventListener("keydown", event => {
    const keyIndex = movementKeyIndex.get(movementKeyForEvent(event));
    if (keyIndex === undefined) {
      return;
    }
    event.preventDefault();
    if (!movementDown[keyIndex]) {
      movementPressed[keyIndex] = 1;
    }
    movementDown[keyIndex] = 1;
  });
  addEventListener("keyup", event => {
    const keyIndex = movementKeyIndex.get(movementKeyForEvent(event));
    if (keyIndex === undefined) {
      return;
    }
    event.preventDefault();
    if (movementDown[keyIndex]) {
      movementReleased[keyIndex] = 1;
    }
    movementDown[keyIndex] = 0;
  });
  addEventListener("blur", () => {
    for (let keyIndex = 0; keyIndex < movementDown.length; keyIndex += 1) {
      if (movementDown[keyIndex]) {
        movementReleased[keyIndex] = 1;
      }
      movementDown[keyIndex] = 0;
    }
  });
  canvas.addEventListener("mousemove", event => {
    const rect = canvas.getBoundingClientRect();
    mouseX = Math.floor((event.clientX - rect.left) * canvas.width / rect.width);
    mouseY = Math.floor((event.clientY - rect.top) * canvas.height / rect.height);
  });
  canvas.addEventListener("mousedown", event => {
    if (event.button !== 0) return;
    mouseButtonsDown |= 1;
    mouseButtonsPressed |= 1;
  });
  canvas.addEventListener("mouseup", event => {
    if (event.button !== 0) return;
    mouseButtonsDown &= ~1;
    mouseButtonsReleased |= 1;
  });

  // Jai currently emits wasm64; its imported memory therefore uses 64-bit addresses.
  // Keep these limits in sync with the current linker output (18 64 KiB pages).
  // Imported shared memory must not declare a larger maximum than the WASM module.
  const memory = new WebAssembly.Memory({ initial: 23n, maximum: 23n, shared: true, address: "i64" });
  const imports = { env: new Proxy({ ...jai_imports, memory }, { get: (target, name) => target[name] ?? (() => 0) }) };
  const response = await fetch("molecule.wasm");
  const { instance } = await WebAssembly.instantiateStreaming(response, imports);
  wasm = instance.exports;
  jai_exports = wasm;
  jai_context = wasm.__jai_runtime_init(0, 0n);
  jai_imports.js_memory_grew();
  await WebAssembly.promising(wasm.wasm_init)();
  wasm_frame = WebAssembly.promising(wasm.wasm_frame);
  requestAnimationFrame(frame);
}

async function frame() {
  writeWasmFrameInput({
    deltaSeconds: 1 / 60,
    windowWidth: innerWidth,
    windowHeight: innerHeight,
    framebufferWidth: canvas.width,
    framebufferHeight: canvas.height,
    movementDown,
    movementPressed,
    movementReleased,
    mouseX,
    mouseY,
    mouseButtonsDown,
    mouseButtonsPressed,
    mouseButtonsReleased,
  });
  movementPressed.fill(0);
  movementReleased.fill(0);
  mouseButtonsPressed = 0;
  mouseButtonsReleased = 0;
  await wasm_frame();
  requestAnimationFrame(frame);
}

boot().catch(error => { console.error(error); document.body.dataset.error = error.message; });
