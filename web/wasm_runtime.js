// Shared state for the browser platform bridge. The other two scripts only
// marshal Jai WebGPU calls; no renderer state or rendering decisions live here.
var jai_imports = {};
var jai_exports = null;
var jai_context = null;
let fetchedAssetBlob = null;
let wasmFrameInput = null;
const assetRequests = [null];

function readWasmUtf8(data, count) {
  const sharedBytes = new Uint8Array(jai_exports.memory.buffer, Number(data), Number(count));
  return new TextDecoder().decode(new Uint8Array(sharedBytes));
}

jai_imports.jsLog = (params_ptr, returns_ptr) => {
  const memory = new DataView(jai_exports.memory.buffer);
  const data = memory.getBigUint64(Number(params_ptr), true);
  const count = memory.getBigUint64(Number(params_ptr) + 8, true);
  const sharedBytes = new Uint8Array(jai_exports.memory.buffer, Number(data), Number(count));
  const copiedBytes = new Uint8Array(sharedBytes);
  console.log(new TextDecoder().decode(copiedBytes));
};

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
    mouseDeltaOffset: memory.getBigUint64(Number(params_ptr) + 72, true),
    mouseWheelOffset: memory.getBigUint64(Number(params_ptr) + 80, true),
    mouseButtonsDownOffset: memory.getBigUint64(Number(params_ptr) + 88, true),
    mouseButtonsPressedOffset: memory.getBigUint64(Number(params_ptr) + 96, true),
    mouseButtonsReleasedOffset: memory.getBigUint64(Number(params_ptr) + 104, true),
    movementKeyCount: memory.getBigUint64(Number(params_ptr) + 112, true),
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
  memory.setInt32(inputAddress + Number(wasmFrameInput.mouseDeltaOffset), frame.mouseDeltaX, true);
  memory.setInt32(inputAddress + Number(wasmFrameInput.mouseDeltaOffset) + 4, frame.mouseDeltaY, true);
  memory.setInt32(inputAddress + Number(wasmFrameInput.mouseWheelOffset), frame.mouseWheelSteps, true);
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

jai_imports.jsAssetRequestAsync = (params_ptr, returns_ptr) => {
  const memory = new DataView(jai_exports.memory.buffer);
  const data = memory.getBigUint64(Number(params_ptr), true);
  const count = memory.getBigUint64(Number(params_ptr) + 8, true);
  const path = readWasmUtf8(data, count);
  const request = {
    state: 1,
    bytesReceived: 0n,
    bytesTotal: 0n,
    errorCode: 0,
    data: null,
  };
  const handle = assetRequests.length;
  assetRequests.push(request);
  fetch(`/assets/${path}`)
    .then(response => {
      if (!response.ok) {
        throw new Error(`GET ${path} returned ${response.status}`);
      }
      const contentLength = response.headers.get("content-length");
      request.bytesTotal = contentLength ? BigInt(contentLength) : 0n;
      return response.arrayBuffer();
    })
    .then(dataBuffer => {
      request.data = dataBuffer;
      request.bytesReceived = BigInt(dataBuffer.byteLength);
      request.bytesTotal = request.bytesReceived;
      request.state = 2;
    })
    .catch(error => {
      request.state = 3;
      request.errorCode = 1;
      console.error("Molecule asset request failed:", error);
    });
  memory.setUint32(Number(returns_ptr), handle, true);
};

jai_imports.jsAssetGetStatus = (params_ptr, returns_ptr) => {
  const memory = new DataView(jai_exports.memory.buffer);
  const handle = memory.getUint32(Number(params_ptr), true);
  const request = assetRequests[handle];
  const state = request?.state ?? 3;
  memory.setUint8(Number(returns_ptr), state);
  memory.setBigUint64(Number(returns_ptr) + 8, request?.bytesReceived ?? 0n, true);
  memory.setBigUint64(Number(returns_ptr) + 16, request?.bytesTotal ?? 0n, true);
  memory.setUint32(Number(returns_ptr) + 24, request?.errorCode ?? 1, true);
};

jai_imports.jsAssetTakeByteCount = (params_ptr, returns_ptr) => {
  const memory = new DataView(jai_exports.memory.buffer);
  const handle = memory.getUint32(Number(params_ptr), true);
  const request = assetRequests[handle];
  const byteCount = request?.state === 2 && request.data ? request.data.byteLength : 0;
  memory.setBigUint64(Number(returns_ptr), BigInt(byteCount), true);
};

jai_imports.jsAssetTakeCopyAndClose = (params_ptr, returns_ptr) => {
  const memory = new DataView(jai_exports.memory.buffer);
  const handle = memory.getUint32(Number(params_ptr), true);
  const destination = memory.getBigUint64(Number(params_ptr) + 8, true);
  const byteCount = memory.getBigUint64(Number(params_ptr) + 16, true);
  const request = assetRequests[handle];
  if (!request?.data || BigInt(request.data.byteLength) !== byteCount) {
    console.error(`Molecule asset take failed for handle ${handle}.`);
    return;
  }
  new Uint8Array(jai_exports.memory.buffer, Number(destination), Number(byteCount))
    .set(new Uint8Array(request.data));
  assetRequests[handle] = null;
};


