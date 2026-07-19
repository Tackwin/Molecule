"""Local development server for Molecule's browser build.

Run from the repository root or this directory:
    python web/server.py
Then open http://localhost:8000/.
"""

from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse
import shutil
import mimetypes
import os


PORT = 8000
WEB_ROOT = Path(__file__).resolve().parent
ASSET_BLOB_PATH = WEB_ROOT.parent / "build" / "assets.blob"
ASSETS_ROOT = WEB_ROOT.parent / "Assets"


class MoleculeHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/assets.blob":
            self.serve_asset_blob(send_body=True)
            return
        if parsed.path.startswith("/assets/"):
            self.serve_asset_file(parsed.path[len("/assets/"):], send_body=True)
            return
        super().do_GET()

    def do_HEAD(self):
        parsed = urlparse(self.path)
        if parsed.path == "/assets.blob":
            self.serve_asset_blob(send_body=False)
            return
        if parsed.path.startswith("/assets/"):
            self.serve_asset_file(parsed.path[len("/assets/"):], send_body=False)
            return
        super().do_HEAD()

    def resolve_asset_path(self, relative_path):
        candidate = (ASSETS_ROOT / relative_path).resolve()
        try:
            candidate.relative_to(ASSETS_ROOT.resolve())
        except ValueError:
            return None
        return candidate

    def serve_asset_file(self, relative_path, send_body):
        asset_path = self.resolve_asset_path(relative_path)
        if asset_path is None or not asset_path.is_file():
            self.send_error(404, "Asset not found")
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(asset_path.stat().st_size))
        self.end_headers()
        if send_body:
            with asset_path.open("rb") as asset_file:
                shutil.copyfileobj(asset_file, self.wfile)

    def serve_asset_blob(self, send_body):
        if not ASSET_BLOB_PATH.is_file():
            self.send_error(404, "Asset blob has not been built")
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(ASSET_BLOB_PATH.stat().st_size))
        self.end_headers()
        if send_body:
            with ASSET_BLOB_PATH.open("rb") as asset_blob:
                shutil.copyfileobj(asset_blob, self.wfile)

    def end_headers(self):
        # Required for the shared WebAssembly memory used by Jai's wasm64 output.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def main():
    mimetypes.add_type("application/wasm", ".wasm")
    os.chdir(WEB_ROOT)
    server = ThreadingHTTPServer(("localhost", PORT), MoleculeHandler)
    print(f"Serving {WEB_ROOT} at http://localhost:{PORT}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
