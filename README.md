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