# Circles shared local service

Run `python server/circles_api.py --port 8090` from the project root. Python's standard library is sufficient. The service binds to `127.0.0.1` and persists SQLite data in `.data/circles.sqlite3`. Use `--database` to select a separate database. No accounts or content are preloaded.

The Flutter web preview discovers port 8090 when opened from localhost. For a separately hosted API, compile Flutter with `--dart-define=CIRCLES_API_URL=https://your-api.example`. Native builds require an explicit service URL. Android's release manifest includes internet access; use HTTPS for a hosted API. Native networking and native binaries have not been validated on this Windows setup.

## Behavior

- Registration requires a unique 3–30 character handle, a 10–128 character password, a display name, and a learning-interest path. Learners control discovery visibility.
- Circles are owned by learners and scoped to an interest. Invite recipients must share that interest and explicitly accept; circle membership is capped at 12, including the owner. Changing interest creates a corresponding owned circle without publishing to old circles.
- Mentor offers are self-declared volunteer offers, not administrator approvals. Availability and discovery controls determine listing. Guidance requests are private to the learner and the selected mentor. Only that mentor can accept or decline.
- Work posts are visible to members of the selected circle. Only the author can edit or remove them. Deleted posts are removed from feeds and award totals; the database retains a soft-deletion record and award fingerprint to prevent repeated rewards.
- An eligible distinct post earns 10 points, at most three awards per Lagos calendar day. The original normalized body is fingerprinted per author, including removed posts. Editing does not award points. Deleting removes its active points but does not reclaim a daily award slot. A new title or URL does not make an identical body eligible again. At most 20 posts can be created per UTC day.
- Posting awards are calculated by the service and are not accepted from the client. SQLite transactions serialize invitation acceptance and post award decisions.
- Device lessons still earn 20 points. Flutter displays these plus account posting points. Posting does not complete lessons or alter learning streaks.

## Endpoints

All authenticated endpoints use `Authorization: Bearer <token>` and JSON request bodies. Sessions last 30 days and sign-out revokes the current token.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Local service availability |
| POST | `/auth/register`, `/auth/login`, `/auth/logout` | Account sessions |
| GET | `/state` | Own profile, circles, eligible peers, mentors, invitations, requests and circle-scoped posts |
| POST | `/profile` | Discovery visibility and interest |
| POST | `/invites` | Invite a same-interest peer |
| POST | `/invites/:id/respond` | Recipient accepts or declines |
| POST | `/mentor-offer` | Publish or pause a volunteer offer |
| POST | `/guidance` | Request a mentor |
| POST | `/guidance/:id/respond` | Mentor responds |
| POST | `/posts` | Share work with a joined circle |
| PATCH, DELETE | `/posts/:id` | Author edits or removes work |

## Validation and scope

Run `python -m unittest discover -s server/tests -v`. Tests use isolated temporary databases with explicitly named test identities and do not populate the live preview database.

Passwords use PBKDF2-HMAC-SHA256 with per-account random salts and 210,000 iterations. Session tokens are random and stored as hashes server-side. Authentication attempts are limited; request sizes, text lengths, membership, ownership, interest and HTTPS project links are validated. CORS allows local HTTP preview origins; credentials and user content are not written to HTTP logs.

This is a loopback development service, not a public hosted community. Public deployment needs an appropriate production server and HTTPS, explicit origin configuration, backups, account recovery, moderation/reporting, operational rate limiting and a deployment-specific data policy. Do not expose the Python development server directly to the internet. The current implementation has no push notifications, file uploads, live chat or automated mentor vetting.
