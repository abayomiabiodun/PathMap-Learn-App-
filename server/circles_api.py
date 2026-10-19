"""Local shared Circles API. Run: python server/circles_api.py --port 8090.

No sample accounts are created. SQLite stores accounts and real user actions.
Use a hosted authenticated service before enabling access beyond this computer.
"""
import argparse
import datetime as dt
import hashlib
import hmac
import json
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

PATHS = {'data', 'web', 'cyber', 'ai', 'design', 'marketing', 'business', 'writing', 'project', 'teaching'}


class ApiError(Exception):
    def __init__(self, message, status=400):
        self.message, self.status = message, status


class CirclesService:
    def __init__(self, database):
        self.database = str(database)
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        with self.db() as db:
            db.executescript('''
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, handle TEXT UNIQUE NOT NULL, name TEXT NOT NULL, salt TEXT NOT NULL, password_hash TEXT NOT NULL, path TEXT NOT NULL, discoverable INTEGER NOT NULL DEFAULT 1, mentor_bio TEXT NOT NULL DEFAULT '', mentor_available INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS circles(id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES users(id), path TEXT NOT NULL, UNIQUE(owner,path));
            CREATE TABLE IF NOT EXISTS members(circle_id TEXT NOT NULL REFERENCES circles(id), user_id TEXT NOT NULL REFERENCES users(id), PRIMARY KEY(circle_id,user_id));
            CREATE TABLE IF NOT EXISTS invites(id TEXT PRIMARY KEY, circle_id TEXT NOT NULL REFERENCES circles(id), sender TEXT NOT NULL REFERENCES users(id), recipient TEXT NOT NULL REFERENCES users(id), status TEXT NOT NULL DEFAULT 'pending', created TEXT NOT NULL);
            CREATE UNIQUE INDEX IF NOT EXISTS pending_invite ON invites(circle_id,recipient) WHERE status='pending';
            CREATE TABLE IF NOT EXISTS guidance(id TEXT PRIMARY KEY, learner TEXT NOT NULL REFERENCES users(id), mentor TEXT NOT NULL REFERENCES users(id), path TEXT NOT NULL, message TEXT NOT NULL, reply TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created TEXT NOT NULL);
            CREATE UNIQUE INDEX IF NOT EXISTS pending_guidance ON guidance(learner,mentor) WHERE status='pending';
            CREATE TABLE IF NOT EXISTS posts(id TEXT PRIMARY KEY, author TEXT NOT NULL REFERENCES users(id), circle_id TEXT NOT NULL REFERENCES circles(id), title TEXT NOT NULL, body TEXT NOT NULL, url TEXT NOT NULL, created TEXT NOT NULL, updated TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS awards(post_id TEXT PRIMARY KEY REFERENCES posts(id), author TEXT NOT NULL REFERENCES users(id), fingerprint TEXT NOT NULL, day TEXT NOT NULL, UNIQUE(author,fingerprint));
            CREATE TABLE IF NOT EXISTS login_attempts(identity TEXT NOT NULL, at INTEGER NOT NULL);
            ''')

    @contextmanager
    def db(self):
        connection = sqlite3.connect(self.database, timeout=20)
        connection.row_factory = sqlite3.Row
        connection.execute('PRAGMA foreign_keys=ON')
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    @staticmethod
    def now():
        return dt.datetime.now(dt.timezone.utc).isoformat()

    @staticmethod
    def day():
        return dt.datetime.now(dt.timezone(dt.timedelta(hours=1))).date().isoformat()

    @staticmethod
    def text(data, key, minimum, maximum):
        value = data.get(key, '')
        if not isinstance(value, str) or not minimum <= len(value.strip()) <= maximum:
            raise ApiError('Check the form fields and try again.')
        return value.strip()

    @staticmethod
    def password_hash(password, salt):
        return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 210000).hex()

    def session(self, db, user):
        token = secrets.token_urlsafe(36)
        db.execute('INSERT INTO sessions VALUES(?,?,?)', (hashlib.sha256(token.encode()).hexdigest(), user, int(time.time()) + 30 * 86400))
        return {'token': token}

    def user(self, db, token):
        row = db.execute('SELECT u.* FROM users u JOIN sessions s ON s.user_id=u.id WHERE s.token_hash=? AND s.expires>?', (hashlib.sha256((token or '').encode()).hexdigest(), int(time.time()))).fetchone()
        if not row:
            raise ApiError('Your session expired. Please sign in again.', 401)
        return row

    @staticmethod
    def own_circle(db, user):
        row = db.execute('SELECT id FROM circles WHERE owner=? AND path=?', (user['id'], user['path'])).fetchone()
        if row:
            return row['id']
        circle = secrets.token_hex(16)
        db.execute('INSERT INTO circles VALUES(?,?,?)', (circle, user['id'], user['path']))
        db.execute('INSERT INTO members VALUES(?,?)', (circle, user['id']))
        return circle

    def dispatch(self, method, route, data, token='', identity='local'):
        with self.db() as db:
            if method == 'GET' and route == '/health':
                return {'status': 'ready', 'mode': 'local-shared'}
            if method == 'POST' and route in ['/auth/register', '/auth/login']:
                handle = self.text(data, 'handle', 3, 30).lower()
                password = data.get('password', '')
                if not re.fullmatch(r'[a-z0-9_-]{3,30}', handle) or not isinstance(password, str) or not 10 <= len(password) <= 128:
                    raise ApiError('Use a handle of 3–30 letters or numbers and a password of 10–128 characters.')
                stamp = int(time.time())
                fingerprint = hashlib.sha256(identity.encode()).hexdigest()
                db.execute('DELETE FROM login_attempts WHERE at<?', (stamp - 900,))
                if db.execute('SELECT COUNT(*) FROM login_attempts WHERE identity=?', (fingerprint,)).fetchone()[0] >= 30:
                    raise ApiError('Too many attempts. Please try again later.', 429)
                # Save failures too: this independent write is committed before validation.
                db.execute('INSERT INTO login_attempts VALUES(?,?)', (fingerprint, stamp))
                db.commit()
                if route == '/auth/register':
                    name = self.text(data, 'name', 2, 40)
                    path = data.get('path')
                    if path not in PATHS:
                        raise ApiError('Find your learning path first.')
                    if db.execute('SELECT 1 FROM users WHERE handle=?', (handle,)).fetchone():
                        raise ApiError('That handle is unavailable. Choose another.')
                    user_id, salt = secrets.token_hex(16), secrets.token_hex(16)
                    db.execute('INSERT INTO users(id,handle,name,salt,password_hash,path) VALUES(?,?,?,?,?,?)', (user_id, handle, name, salt, self.password_hash(password, salt), path))
                    self.own_circle(db, db.execute('SELECT * FROM users WHERE id=?', (user_id,)).fetchone())
                    return self.session(db, user_id)
                user = db.execute('SELECT * FROM users WHERE handle=?', (handle,)).fetchone()
                calculated = self.password_hash(password, user['salt'] if user else '00' * 16)
                if not user or not hmac.compare_digest(calculated, user['password_hash']):
                    raise ApiError('The handle or password is incorrect.', 401)
                return self.session(db, user['id'])

            me = self.user(db, token)
            uid = me['id']
            if method != 'GET':
                db.execute('BEGIN IMMEDIATE')
            if method == 'POST' and route == '/auth/logout':
                db.execute('DELETE FROM sessions WHERE token_hash=?', (hashlib.sha256(token.encode()).hexdigest(),))
                return {'ok': True}
            if method == 'GET' and route == '/state':
                return self.state(db, me)
            if method == 'POST' and route == '/profile':
                path = data.get('path', me['path'])
                if path not in PATHS or not isinstance(data.get('discoverable', True), bool):
                    raise ApiError('Check the form fields and try again.')
                db.execute('UPDATE users SET path=?,discoverable=? WHERE id=?', (path, int(data.get('discoverable', True)), uid))
                self.own_circle(db, db.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone())
                return {'ok': True}
            if method == 'POST' and route == '/invites':
                target = db.execute('SELECT * FROM users WHERE id=? AND path=? AND discoverable=1', (data.get('learner'), me['path'])).fetchone()
                if not target or target['id'] == uid:
                    raise ApiError('Choose another learner with the same interest.')
                circle = self.own_circle(db, me)
                if db.execute('SELECT 1 FROM members WHERE circle_id=? AND user_id=?', (circle, target['id'])).fetchone():
                    raise ApiError('This learner is already in your circle.')
                if db.execute("SELECT 1 FROM invites WHERE circle_id=? AND recipient=? AND status='pending'", (circle, target['id'])).fetchone():
                    raise ApiError('A request is already pending.')
                db.execute('INSERT INTO invites(id,circle_id,sender,recipient,created) VALUES(?,?,?,?,?)', (secrets.token_hex(16), circle, uid, target['id'], self.now()))
                return {'ok': True}
            match = re.fullmatch(r'/invites/([a-f0-9]+)/respond', route)
            if method == 'POST' and match:
                invitation = db.execute("SELECT i.*,c.path FROM invites i JOIN circles c ON c.id=i.circle_id WHERE i.id=? AND recipient=? AND status='pending'", (match[1], uid)).fetchone()
                if not invitation or type(data.get('accept')) is not bool:
                    raise ApiError('This request is no longer available.', 404)
                if data['accept']:
                    if invitation['path'] != me['path']:
                        raise ApiError('This circle is for a different learning interest.')
                    if db.execute('SELECT COUNT(*) FROM members WHERE circle_id=?', (invitation['circle_id'],)).fetchone()[0] >= 12:
                        raise ApiError('This circle is full. Try another circle.')
                    db.execute('INSERT OR IGNORE INTO members VALUES(?,?)', (invitation['circle_id'], uid))
                db.execute('UPDATE invites SET status=? WHERE id=?', ('accepted' if data['accept'] else 'declined', match[1]))
                return {'ok': True}
            if method == 'POST' and route == '/mentor-offer':
                bio = self.text(data, 'bio', 30, 1000)
                if type(data.get('available')) is not bool:
                    raise ApiError('Check the form fields and try again.')
                db.execute('UPDATE users SET mentor_bio=?,mentor_available=? WHERE id=?', (bio, int(data['available']), uid))
                return {'ok': True}
            if method == 'POST' and route == '/guidance':
                mentor = db.execute('SELECT id FROM users WHERE id=? AND path=? AND mentor_available=1 AND discoverable=1 AND id<>?', (data.get('mentor'), me['path'], uid)).fetchone()
                if not mentor:
                    raise ApiError('This mentor is not available for your path.')
                message = self.text(data, 'message', 20, 2000)
                if db.execute("SELECT 1 FROM guidance WHERE learner=? AND mentor=? AND status='pending'", (uid, mentor['id'])).fetchone():
                    raise ApiError('A request is already pending.')
                db.execute('INSERT INTO guidance(id,learner,mentor,path,message,created) VALUES(?,?,?,?,?,?)', (secrets.token_hex(16), uid, mentor['id'], me['path'], message, self.now()))
                return {'ok': True}
            match = re.fullmatch(r'/guidance/([a-f0-9]+)/respond', route)
            if method == 'POST' and match:
                row = db.execute("SELECT * FROM guidance WHERE id=? AND mentor=? AND status='pending'", (match[1], uid)).fetchone()
                if not row or type(data.get('accept')) is not bool:
                    raise ApiError('This request is no longer available.', 404)
                reply = self.text(data, 'reply', 0, 2000)
                db.execute('UPDATE guidance SET status=?,reply=? WHERE id=?', ('accepted' if data['accept'] else 'declined', reply, match[1]))
                return {'ok': True}
            if method == 'POST' and route == '/posts':
                circle = db.execute('SELECT c.* FROM circles c JOIN members m ON m.circle_id=c.id WHERE c.id=? AND m.user_id=? AND c.path=?', (data.get('circle'), uid, me['path'])).fetchone()
                if not circle:
                    raise ApiError('Join this circle before sharing work.', 403)
                title, body, url = self.post_fields(data)
                today = self.day()
                # Serialize the award decision and post insert across concurrent requests.
                count = db.execute('SELECT COUNT(*) FROM posts WHERE author=? AND substr(created,1,10)=?', (uid, self.now()[:10])).fetchone()[0]
                if count >= 20:
                    raise ApiError('You have reached today’s posting limit. Try again tomorrow.', 429)
                pid, now = secrets.token_hex(16), self.now()
                db.execute('INSERT INTO posts VALUES(?,?,?,?,?,?,?,?,0)', (pid, uid, circle['id'], title, body, url, now, now))
                fingerprint = hashlib.sha256(re.sub(r'\s+', ' ', body.casefold()).strip().encode()).hexdigest()
                awarded = db.execute('SELECT COUNT(*) FROM awards WHERE author=? AND day=?', (uid, today)).fetchone()[0]
                if awarded < 3:
                    db.execute('INSERT OR IGNORE INTO awards VALUES(?,?,?,?)', (pid, uid, fingerprint, today))
                return {'id': pid}
            match = re.fullmatch(r'/posts/([a-f0-9]+)', route)
            if match and method in ['PATCH', 'DELETE']:
                post = db.execute('SELECT * FROM posts WHERE id=? AND author=? AND removed=0', (match[1], uid)).fetchone()
                if not post:
                    raise ApiError('You can only edit or delete your own active posts.', 403)
                if method == 'DELETE':
                    db.execute('UPDATE posts SET removed=1,updated=? WHERE id=?', (self.now(), match[1]))
                else:
                    title, body, url = self.post_fields(data)
                    db.execute('UPDATE posts SET title=?,body=?,url=?,updated=? WHERE id=?', (title, body, url, self.now(), match[1]))
                return {'ok': True}
            raise ApiError('This action is not available.', 404)

    def post_fields(self, data):
        title, body = self.text(data, 'title', 3, 100), self.text(data, 'body', 40, 4000)
        url = self.text(data, 'url', 0, 500)
        if url and (urlparse(url).scheme != 'https' or not urlparse(url).hostname or urlparse(url).username):
            raise ApiError('Use a valid HTTPS project link.')
        return title, body, url

    def state(self, db, me):
        uid, path = me['id'], me['path']
        own = self.own_circle(db, me)
        profile = {k: me[k] for k in ['id', 'handle', 'name', 'path', 'discoverable', 'mentor_bio', 'mentor_available']}
        profile['post_points'] = db.execute('SELECT COUNT(*)*10 FROM awards a JOIN posts p ON p.id=a.post_id WHERE a.author=? AND p.removed=0', (uid,)).fetchone()[0]
        def rows(sql, args=()):
            return [dict(r) for r in db.execute(sql, args).fetchall()]
        learners = rows("SELECT u.id,u.name,u.path,EXISTS(SELECT 1 FROM members WHERE circle_id=? AND user_id=u.id) AS member,EXISTS(SELECT 1 FROM invites WHERE circle_id=? AND recipient=u.id AND status='pending') AS pending FROM users u WHERE u.path=? AND discoverable=1 AND id<>? ORDER BY u.name LIMIT 100", (own, own, path, uid))
        circles = rows('SELECT c.id,c.path,u.name AS owner_name,(SELECT COUNT(*) FROM members WHERE circle_id=c.id) AS members,c.owner=? AS own FROM circles c JOIN members m ON m.circle_id=c.id JOIN users u ON u.id=c.owner WHERE m.user_id=? AND c.path=? ORDER BY own DESC,u.name', (uid, uid, path))
        return {'profile': profile, 'own_circle': own, 'circles': circles, 'learners': learners,
            'members': rows('SELECT u.id,u.name FROM members m JOIN users u ON u.id=m.user_id WHERE m.circle_id=? ORDER BY u.name', (own,)),
            'invites': rows('SELECT i.id,i.status,i.created,s.name AS sender_name,r.name AS recipient_name,i.recipient=? AS incoming FROM invites i JOIN users s ON s.id=i.sender JOIN users r ON r.id=i.recipient WHERE i.sender=? OR i.recipient=? ORDER BY i.created DESC LIMIT 100', (uid, uid, uid)),
            'mentors': rows('SELECT id,name,path,mentor_bio FROM users WHERE path=? AND mentor_available=1 AND discoverable=1 AND id<>? ORDER BY name LIMIT 100', (path, uid)),
            'guidance': rows('SELECT g.id,g.message,g.reply,g.status,g.created,l.name AS learner_name,m.name AS mentor_name,g.mentor=? AS mentor_side FROM guidance g JOIN users l ON l.id=g.learner JOIN users m ON m.id=g.mentor WHERE g.learner=? OR g.mentor=? ORDER BY g.created DESC LIMIT 100', (uid, uid, uid)),
            'posts': rows('SELECT p.id,p.title,p.body,p.url,p.created,p.updated,p.circle_id,u.name AS author_name,o.name AS circle_owner,p.author=? AS own,CASE WHEN a.post_id IS NULL THEN 0 ELSE 10 END AS points FROM posts p JOIN users u ON u.id=p.author JOIN circles c ON c.id=p.circle_id JOIN users o ON o.id=c.owner LEFT JOIN awards a ON a.post_id=p.id WHERE p.removed=0 AND c.path=? AND EXISTS(SELECT 1 FROM members WHERE circle_id=c.id AND user_id=?) ORDER BY p.created DESC LIMIT 100', (uid, path, uid))}


def handler(service):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass  # Do not log passwords, bearer tokens or user content.

        def headers_out(self, status):
            self.send_response(status)
            origin = self.headers.get('Origin', '')
            parsed = urlparse(origin)
            if parsed.scheme == 'http' and parsed.hostname in ['localhost', '127.0.0.1', '::1']:
                self.send_header('Access-Control-Allow-Origin', origin)
                self.send_header('Vary', 'Origin')
            self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
            self.send_header('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.end_headers()

        def do_OPTIONS(self):
            self.headers_out(204)

        def handle_api(self):
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if length < 0 or length > 32768:
                    raise ApiError('This request is too large.', 413)
                data = json.loads(self.rfile.read(length)) if length else {}
                if not isinstance(data, dict):
                    raise ApiError('Check the form fields and try again.')
                authorization = self.headers.get('Authorization', '')
                token = authorization[7:] if authorization.startswith('Bearer ') else ''
                result = service.dispatch(self.command, urlparse(self.path).path, data, token, self.client_address[0])
                self.headers_out(200)
                self.wfile.write(json.dumps(result, ensure_ascii=False).encode())
            except ApiError as error:
                self.headers_out(error.status)
                self.wfile.write(json.dumps({'error': error.message}, ensure_ascii=False).encode())
            except (ValueError, TypeError):
                self.headers_out(400)
                self.wfile.write(b'{"error":"Check the form fields and try again."}')
            except Exception:
                self.headers_out(500)
                self.wfile.write(b'{"error":"The community service could not complete this action. Try again."}')

        do_GET = do_POST = do_PATCH = do_DELETE = handle_api
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8090)
    parser.add_argument('--database', default=str(Path(__file__).resolve().parents[1] / '.data/circles.sqlite3'))
    options = parser.parse_args()
    service = CirclesService(options.database)
    print(f'Circles local shared API ready on http://127.0.0.1:{options.port}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', options.port), handler(service)).serve_forever()
