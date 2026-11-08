#!/usr/bin/env python3
"""Serves a directory on loopback, with the wasm MIME type and CORS, no caching.

Used for the Flutter web builds and for a local rive_native wasm host:

    python3 tool/serve.py <directory> --port 8123
"""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.mjs': 'text/javascript', '.js': 'text/javascript'}

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('--port', type=int, default=8123)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, directory=args.directory))
    print(f'Serving {args.directory} at http://127.0.0.1:{args.port}', flush=True)
    server.serve_forever()
