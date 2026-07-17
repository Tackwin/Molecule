// Shared state for the browser platform bridge. The other two scripts only
// marshal Jai WebGPU calls; no renderer state or rendering decisions live here.
var jai_imports = {};
var jai_exports = null;
var jai_context = null;
