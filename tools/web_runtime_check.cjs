const { chromium } = require("playwright");
const path = require("path");

const page_url = process.argv[2] ?? "http://localhost:8000/";
const viewport_width = Number(process.env.WEB_RUNTIME_WIDTH ?? 1280);
const viewport_height = Number(process.env.WEB_RUNTIME_HEIGHT ?? 720);
const hold_ms = Number(process.env.WEB_RUNTIME_HOLD_MS ?? 0);

(async () => {
  const browser = await chromium.launch({
    headless: true,
    // Playwright's headless shell does not expose a SwiftShader WebGPU adapter.
    // Use the full locally installed Chromium build instead.
    executablePath: path.join(
      process.env.LOCALAPPDATA,
      "ms-playwright",
      "chromium-1187",
      "chrome-win",
      "chrome.exe",
    ),
    args: [
      "--enable-unsafe-webgpu",
      "--use-webgpu-adapter=swiftshader",
      "--enable-dawn-features=allow_unsafe_apis",
      "--disable-dawn-features=use_dxc",
      "--enable-webgpu-developer-features",
      "--use-gpu-in-tests",
      "--enable-accelerated-2d-canvas",
      "--disable-gpu-sandbox",
    ],
  });
  const page = await browser.newPage({
    viewport: { width: viewport_width, height: viewport_height },
  });
  let failed = false;

  page.on("console", message => {
    console.log(`console:${message.type()}:${message.text()}`);
    if (message.type() === "error") failed = true;
  });
  page.on("pageerror", error => {
    console.log(`pageerror:${error.stack || error.message}`);
    failed = true;
  });

  await page.goto(page_url, { waitUntil: "load" });
  try {
    await page.waitForFunction(
      () => globalThis.moleculeRuntime?.initialized && globalThis.moleculeRuntime.frameCount >= 2,
      null,
      { timeout: 15000 },
    );
  } catch (error) {
    console.log(`runtime-timeout:${JSON.stringify(await page.evaluate(() => globalThis.moleculeRuntime))}`);
    throw error;
  }
  console.log(`runtime:${JSON.stringify(await page.evaluate(() => ({
    initialized: globalThis.moleculeRuntime.initialized,
    frameCount: globalThis.moleculeRuntime.frameCount,
    canvasWidth: document.querySelector("#game").width,
    canvasHeight: document.querySelector("#game").height,
    error: document.body.dataset.error ?? "",
  })))}`);
  if (hold_ms > 0) {
    await page.waitForTimeout(hold_ms);
  }
  await page.evaluate(() => { globalThis.moleculeRuntime.paused = true; });
  await page.waitForTimeout(250);
  await page.screenshot({ path: "web/runtime-check.png", timeout: 120000 });
  await browser.close();
  process.exitCode = failed ? 1 : 0;
})();
