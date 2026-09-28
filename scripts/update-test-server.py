"""Loopback-only server for signed update integration fixtures."""
import functools
import http.server
import pathlib
import sys
import socketserver

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
class LoopbackServer(http.server.ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer's default reverse-DNS lookup can stall on hosted macOS runners.
        socketserver.TCPServer.server_bind(self)
        self.server_name = "localhost"
        self.server_port = self.server_address[1]

server = LoopbackServer(("127.0.0.1", 0), handler)
pathlib.Path(sys.argv[2]).write_text(str(server.server_port))
server.serve_forever()
