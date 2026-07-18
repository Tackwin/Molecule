// Shared state for the browser platform bridge. The other two scripts only
// marshal Jai WebGPU calls; no renderer state or rendering decisions live here.
var jai_imports = {};
var jai_exports = null;
var jai_context = null;
let fetchedAssetBlob = null;

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
