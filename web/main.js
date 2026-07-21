const canvas = document.querySelector("#game");
let wasm;
let wasm_frame;
const moleculeRuntime = {
  phase: "script-loaded",
  initialized: false,
  frameCount: 0,
  paused: false,
};
globalThis.moleculeRuntime = moleculeRuntime;
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
let mouseDeltaX = 0;
let mouseDeltaY = 0;
let mouseWheelSteps = 0;
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
  moleculeRuntime.phase = "booting";
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
    if (mouseButtonsDown & 1) {
      mouseButtonsReleased |= 1;
    }
    if (mouseButtonsDown & 2) {
      mouseButtonsReleased |= 2;
    }
    mouseButtonsDown = 0;
  });
  canvas.addEventListener("contextmenu", event => {
    event.preventDefault();
  });
  canvas.addEventListener("mousemove", event => {
    const rect = canvas.getBoundingClientRect();
    mouseX = Math.floor((event.clientX - rect.left) * canvas.width / rect.width);
    mouseY = Math.floor((event.clientY - rect.top) * canvas.height / rect.height);
    mouseDeltaX += Math.round(event.movementX * canvas.width / rect.width);
    mouseDeltaY += Math.round(event.movementY * canvas.height / rect.height);
  });
  canvas.addEventListener("wheel", event => {
    event.preventDefault();
    mouseWheelSteps += -Math.sign(event.deltaY);
  }, { passive: false });
  canvas.addEventListener("mousedown", event => {
    const rect = canvas.getBoundingClientRect();
    mouseX = Math.floor((event.clientX - rect.left) * canvas.width / rect.width);
    mouseY = Math.floor((event.clientY - rect.top) * canvas.height / rect.height);
    if (event.button === 0) {
      mouseButtonsDown |= 1;
      mouseButtonsPressed |= 1;
      return;
    }
    if (event.button === 2) {
      event.preventDefault();
      mouseButtonsDown |= 2;
      mouseButtonsPressed |= 2;
    }
  });
  // Use window so button-up is captured even when the pointer leaves the canvas.
  window.addEventListener("mouseup", event => {
    if (event.button === 0) {
      mouseButtonsDown &= ~1;
      mouseButtonsReleased |= 1;
      return;
    }
    if (event.button === 2) {
      mouseButtonsDown &= ~2;
      mouseButtonsReleased |= 2;
    }
  });

  // Jai currently emits wasm64 and Walloc owns one fixed shared heap.
  // Keep this page count synchronized with Build.jai's 64 MiB linker limits.
  const wasmMemoryPages = 0x400n;
  const memory = new WebAssembly.Memory({
    initial: wasmMemoryPages,
    maximum: wasmMemoryPages,
    shared: true,
    address: "i64",
  });
  const imports = { env: new Proxy({ ...jai_imports, memory }, { get: (target, name) => target[name] ?? (() => 0) }) };
  const response = await fetch("molecule.wasm");
  const { instance } = await WebAssembly.instantiateStreaming(response, imports);
  moleculeRuntime.phase = "wasm-instantiated";
  wasm = instance.exports;
  console.log(
    "WASM tables:",
    JSON.stringify(Object.entries(wasm)
      .filter(([, value]) => value instanceof WebAssembly.Table)
      .map(([name, value]) => ({ name, length: String(value.length) }))),
  );
  jai_exports = wasm;
  jai_context = wasm.__jai_runtime_init(0, 0n);
  jai_imports.js_memory_grew();
  moleculeRuntime.phase = "game-initializing";
  await WebAssembly.promising(wasm.wasm_init)();
  wasm_frame = WebAssembly.promising(wasm.wasm_frame);
  moleculeRuntime.initialized = true;
  moleculeRuntime.phase = "running";
  requestAnimationFrame(frame);
}

async function frame() {
  if (moleculeRuntime.paused) {
    requestAnimationFrame(frame);
    return;
  }
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
    mouseDeltaX,
    mouseDeltaY,
    mouseWheelSteps,
    mouseButtonsDown,
    mouseButtonsPressed,
    mouseButtonsReleased,
  });
  movementPressed.fill(0);
  movementReleased.fill(0);
  mouseButtonsPressed = 0;
  mouseButtonsReleased = 0;
  mouseDeltaX = 0;
  mouseDeltaY = 0;
  mouseWheelSteps = 0;
  await wasm_frame();
  moleculeRuntime.frameCount += 1;
  requestAnimationFrame(frame);
}

boot().catch(error => {
  moleculeRuntime.phase = "error";
  console.error(error);
  document.body.dataset.error = error.message;
});
