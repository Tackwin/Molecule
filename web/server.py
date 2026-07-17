"""Local development server for Molecule's browser build.

Run from the repository root or this directory:
    python web/server.py
Then open http://localhost:8000/.
"""

from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import mimetypes
import os


PORT = 8000
WEB_ROOT = Path(__file__).resolve().parent


class MoleculeHandler(SimpleHTTPRequestHandler):
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
