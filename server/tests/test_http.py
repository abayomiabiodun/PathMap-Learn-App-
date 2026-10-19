import importlib.util
import json
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

spec = importlib.util.spec_from_file_location('circles_http_api', Path(__file__).resolve().parents[1] / 'circles_api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


class HttpIntegrationTests(unittest.TestCase):
    def test_browser_cors_auth_and_post_points_over_http(self):
        with tempfile.TemporaryDirectory() as temp:
            service = api.CirclesService(Path(temp) / 'http-test.sqlite3')
            server = ThreadingHTTPServer(('127.0.0.1', 0), api.handler(service))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = f'http://127.0.0.1:{server.server_port}'
            try:
                def call(method, path, data=None, token=None, origin='http://127.0.0.1:8081'):
                    headers = {'Origin': origin, 'Content-Type': 'application/json'}
                    if token:
                        headers['Authorization'] = f'Bearer {token}'
                    request = Request(base + path, data=json.dumps(data).encode() if data is not None else None, headers=headers, method=method)
                    return urlopen(request, timeout=5)

                with call('OPTIONS', '/posts') as response:
                    self.assertEqual(response.headers['Access-Control-Allow-Origin'], 'http://127.0.0.1:8081')
                    self.assertIn('Authorization', response.headers['Access-Control-Allow-Headers'])
                with call('GET', '/health', origin='https://untrusted.example') as response:
                    self.assertIsNone(response.headers.get('Access-Control-Allow-Origin'))
                with self.assertRaises(HTTPError) as rejected:
                    call('GET', '/state')
                self.assertEqual(rejected.exception.code, 401)
                with call('POST', '/auth/register', {'handle': 'http-test-user', 'name': 'HTTP test learner', 'password': 'Test-only-password-123', 'path': 'web'}) as response:
                    token = json.load(response)['token']
                with call('GET', '/state', token=token) as response:
                    state = json.load(response)
                with call('POST', '/posts', {'title': 'HTTP test project', 'body': 'A test-only project describing a small accessible page and what I learned from building it.', 'circle': state['own_circle'], 'url': ''}, token) as response:
                    post = json.load(response)['id']
                with call('GET', '/state', token=token) as response:
                    self.assertEqual(json.load(response)['profile']['post_points'], 10)
                with call('DELETE', f'/posts/{post}', token=token):
                    pass
                with call('GET', '/state', token=token) as response:
                    self.assertEqual(json.load(response)['profile']['post_points'], 0)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=3)
