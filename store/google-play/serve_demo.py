# Serves demo/*.json with CORS so the web app tab (another localhost port) can fetch them.
import http.server, os, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'demo'))
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*'); self.send_header('Cache-Control', 'no-store')
        super().end_headers()
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 8095), H).serve_forever()
