# todo

## Authentication and device sessions

Auth routes are available under both `/auth` and `/api/v1/auth`.

- `POST /auth/login` accepts the email and password. For silent device login,
  Flutter can also send a UUID `device_id` and a 64-character URL-safe
  `device_secret`; send both or neither. Generate the secret from secure random
  bytes and keep it in `flutter_secure_storage`. The API stores only its
  SHA-256 hash.
- `POST /auth/refresh` accepts the current refresh token and returns a new
  access/refresh token pair. Replace both saved tokens after success.
- If refresh fails after its expiry, `POST /auth/device-login` accepts
  `user_id`, `device_id`, and `device_secret` and issues a new pair.
- `GET /auth/devices` lists the signed-in user's devices.
  `DELETE /auth/devices/{device_id}` revokes one device; its refresh tokens and
  device-bound access tokens stop working.
- `POST /auth/logout` revokes the device associated with the submitted refresh
  token. `POST /auth/logout-all` revokes all sessions and device credentials.

Device secrets are long-lived credentials: anyone who extracts one from a
device can attempt silent login until that device is revoked. Use HTTPS and
never log device secrets or tokens. Password login is required to re-enable a
revoked device credential.

## Roles and user administration

New self-registered accounts always receive the `user` role. User roles are
read from MongoDB on each authenticated request; the client cannot grant or
change its own role.

The `admin` role can manage users through `/admin/users` (also available under
`/api/v1/admin/users`):

- `POST` creates a user with a name, email, password, and optional `user` or
  `admin` role.
- `GET` lists users (50 per page by default, maximum 100; use `skip` and
  `limit`) or retrieves one user by ID.
- `PATCH` updates a user's name, email, password, or role. Password changes
  revoke that user's sessions.
- `DELETE` permanently deletes the account, its todos, chat messages, and
  sessions.

The Flutter signed-in screen shows a **Manage users** entry only for accounts
whose authenticated user response has the `admin` role. The API still enforces
the role independently of the UI.

Admins cannot delete or demote themselves, and the last admin cannot be
removed. To bootstrap the first admin, promote a trusted account directly in
MongoDB, for example:

```javascript
db.users.updateOne(
  { email: "trusted-admin@example.com" },
  { $set: { role: "admin" } }
)
```

## One-to-one chat

Signed-in users can open **Chat with a user** and search registered accounts by
email through `GET /chat/users?search=<email-fragment>`. Chat history is stored
in MongoDB and loaded from `GET /chat/{peer_id}/messages` (latest 100
messages). Live delivery uses `/chat/ws/{peer_id}` (also available under
`/api/v1/chat/ws/{peer_id}`). The first WebSocket frame authenticates with the
access token; tokens are not placed in the URL.

After connecting, send `{"type":"authenticate","token":"<access-token>"}`.
Once the server replies with `type: "ready"`, send
`{"type":"message","content":"Hello"}` frames. Both participants receive
`type: "message"` events containing the persisted message.

Live socket delivery uses Redis Pub/Sub, so messages reach connected users on
different FastAPI workers. `REDIS_URL` configures the connection;
`backend/docker-compose.yml` starts Redis locally. The API checks Redis on
startup and shuts down its connection cleanly. Message history remains stored
in MongoDB, not Redis.