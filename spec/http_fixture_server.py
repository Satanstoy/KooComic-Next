"""Local generated-input server; no account/session or production network."""
import json
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


class Handler(SimpleHTTPRequestHandler):
    counts = {}
    generations = []

    def log_message(self, *_):
        pass

    def send_json(self, value):
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlsplit(self.path)
        self.counts[url.path] = self.counts.get(url.path, 0) + 1
        if url.path == "/stats.json":
            self.send_json({"counts": self.counts, "generations": self.generations})
        elif url.path in ("/unauthorized.epub", "/forbidden.epub"):
            self.send_error(401 if url.path == "/unauthorized.epub" else 403)
        elif url.path == "/vol_list.php":
            limit = int(parse_qs(url.query).get("limit", [28])[0])
            generation = self.counts[url.path]
            size = os.path.getsize(os.path.join(self.directory, "source.epub"))
            entries = [{"file_md5": f"service-{i}", "vol_name": f"Service {i}", "file_size": size,
                        "file_url": f"http://{self.headers['Host']}/source.epub?generation={generation}"}
                       for i in range(1, min(limit, 20) + 1)]
            self.send_json({"total": 20, "data": entries})
        else:
            if url.path == "/source.epub" and "generation" in parse_qs(url.query):
                generation = parse_qs(url.query)["generation"][0]
                if generation != str(self.counts.get("/vol_list.php", 0)) or generation == "0":
                    self.send_error(403)
                    return
                self.generations.append(generation)
            super().do_GET()


if __name__ == "__main__":
    directory, port = sys.argv[1], int(sys.argv[2])
    ThreadingHTTPServer(("127.0.0.1", port),
                        lambda *args, **kwargs: Handler(*args, directory=directory, **kwargs)).serve_forever()
