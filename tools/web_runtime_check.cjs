const { chromium } = require("playwright");
const path = require("path");

const page_url = process.argv[2] ?? "http://localhost:8000/";

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
  const page = await browser.newPage();
  let failed = false;

  page.on("console", message => {
    console.log(`console:${message.type()}:${message.text()}`);
    if (message.type() === "error") failed = true;
  });
  page.on("pageerror", error => {
    console.log(`pageerror:${error.stack || error.message}`);
    failed = true;
  });

  await page.goto(page_url, { waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: "web/runtime-check.png" });
  await browser.close();
  process.exitCode = failed ? 1 : 0;
})();
