// Shared state for the browser platform bridge. The other two scripts only
// marshal Jai WebGPU calls; no renderer state or rendering decisions live here.
var jai_imports = {};
var jai_exports = null;
var jai_context = null;
let fetchedAssetBlob = null;
let wasmFrameInput = null;

jai_imports.jsInstallFrameInputBuffer = (params_ptr, returns_ptr) => {
  const memory = new DataView(jai_exports.memory.buffer);
  wasmFrameInput = {
    address: memory.getBigUint64(Number(params_ptr), true),
    byteCount: memory.getBigUint64(Number(params_ptr) + 8, true),
    simulationDeltaSecondsOffset: memory.getBigUint64(Number(params_ptr) + 16, true),
    windowSizePixelsOffset: memory.getBigUint64(Number(params_ptr) + 24, true),
    framebufferSizePixelsOffset: memory.getBigUint64(Number(params_ptr) + 32, true),
    keyboardDownOffset: memory.getBigUint64(Number(params_ptr) + 40, true),
    keyboardPressedOffset: memory.getBigUint64(Number(params_ptr) + 48, true),
    keyboardReleasedOffset: memory.getBigUint64(Number(params_ptr) + 56, true),
    mousePositionOffset: memory.getBigUint64(Number(params_ptr) + 64, true),
    mouseButtonsDownOffset: memory.getBigUint64(Number(params_ptr) + 72, true),
    mouseButtonsPressedOffset: memory.getBigUint64(Number(params_ptr) + 80, true),
    mouseButtonsReleasedOffset: memory.getBigUint64(Number(params_ptr) + 88, true),
    movementKeyCount: memory.getBigUint64(Number(params_ptr) + 96, true),
  };
};

function writeWasmFrameInput(frame) {
  if (!wasmFrameInput) {
    throw new Error("WASM frame input buffer was not installed.");
  }

  const memory = new DataView(jai_exports.memory.buffer);
  const inputAddress = Number(wasmFrameInput.address);
  memory.setFloat32(
    inputAddress + Number(wasmFrameInput.simulationDeltaSecondsOffset),
    frame.deltaSeconds,
    true,
  );
  memory.setInt32(
    inputAddress + Number(wasmFrameInput.windowSizePixelsOffset),
    frame.windowWidth,
    true,
  );
  memory.setInt32(
    inputAddress + Number(wasmFrameInput.windowSizePixelsOffset) + 4,
    frame.windowHeight,
    true,
  );
  memory.setInt32(
    inputAddress + Number(wasmFrameInput.framebufferSizePixelsOffset),
    frame.framebufferWidth,
    true,
  );
  memory.setInt32(
    inputAddress + Number(wasmFrameInput.framebufferSizePixelsOffset) + 4,
    frame.framebufferHeight,
    true,
  );

  for (let keyIndex = 0; keyIndex < Number(wasmFrameInput.movementKeyCount); keyIndex += 1) {
    memory.setUint8(
      inputAddress + Number(wasmFrameInput.keyboardDownOffset) + keyIndex,
      frame.movementDown[keyIndex],
    );
    memory.setUint8(
      inputAddress + Number(wasmFrameInput.keyboardPressedOffset) + keyIndex,
      frame.movementPressed[keyIndex],
    );
    memory.setUint8(
      inputAddress + Number(wasmFrameInput.keyboardReleasedOffset) + keyIndex,
      frame.movementReleased[keyIndex],
    );
  }
  memory.setInt32(inputAddress + Number(wasmFrameInput.mousePositionOffset), frame.mouseX, true);
  memory.setInt32(inputAddress + Number(wasmFrameInput.mousePositionOffset) + 4, frame.mouseY, true);
  memory.setUint8(inputAddress + Number(wasmFrameInput.mouseButtonsDownOffset), frame.mouseButtonsDown);
  memory.setUint8(inputAddress + Number(wasmFrameInput.mouseButtonsPressedOffset), frame.mouseButtonsPressed);
  memory.setUint8(inputAddress + Number(wasmFrameInput.mouseButtonsReleasedOffset), frame.mouseButtonsReleased);
}

jai_imports.jsFetchAssetBlob = new WebAssembly.Suspending(async (params_ptr, returns_ptr) => {
  try {
    const response = await fetch("assets.blob");
    if (!response.ok) {
      throw new Error(`GET assets.blob returned ${response.status}`);
    }
    fetchedAssetBlob = await response.arrayBuffer();
  } catch (error) {
    fetchedAssetBlob = null;
    console.error("Molecule asset blob fetch failed:", error);
  }

  const byteCount = fetchedAssetBlob ? BigInt(fetchedAssetBlob.byteLength) : 0n;
  const memory = new DataView(jai_exports.memory.buffer);
  memory.setBigUint64(Number(returns_ptr), byteCount, true);
});

jai_imports.jsCopyFetchedAssetBlob = (params_ptr, returns_ptr) => {
  if (!fetchedAssetBlob) {
    return;
  }

  const memory = new DataView(jai_exports.memory.buffer);
  const destination = memory.getBigUint64(Number(params_ptr), true);
  const byteCount = memory.getBigUint64(Number(params_ptr) + 8, true);
  if (byteCount !== BigInt(fetchedAssetBlob.byteLength)) {
    console.error("Molecule asset blob copy size does not match fetched data.");
    return;
  }

  const destinationBytes = new Uint8Array(
    jai_exports.memory.buffer,
    Number(destination),
    Number(byteCount),
  );
  destinationBytes.set(new Uint8Array(fetchedAssetBlob));
};
