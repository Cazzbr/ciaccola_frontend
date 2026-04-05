# P2P Chat Flutter Frontend

This project includes:
- HTTP login with token persistence in secure storage
- Contact retrieval after authentication
- Socket.IO for signaling and presence
- WebRTC data channel for P2P messaging
- SQLite local history because the server does not persist chat data
- Delete-for-both sync commands
- Offline queue for outbound messages

## Configure
Update these values in `lib/services/api_config.dart`:
- `baseHttpUrl`
- `baseSocketUrl`
- endpoint paths if your backend differs

## Expected server behavior
- POST `/login` returns `{ "token": "..." }`
- GET `/contacts` with `Authorization: Bearer <token>` returns a list like:
  `[{"id":"u2","name":"Alice"}]`
- Socket.IO authenticates using handshake auth token: `auth: { token }`
- Server relays signaling events only:
  - `offer`
  - `answer`
  - `ice-candidate`
  - `audio-offer`
  - `typing`
  - `stop-typing`

## Signaling notes
Socket.IO is used only for signaling and presence. Actual messages go through the WebRTC data channel whenever available.

## Suggested server events
- `join-room` with `{ room }`
- `user-joined` with `{ userId, username }`
- `offer` { room, from, sdp, type }
- `answer` { room, from, sdp, type }
- `ice-candidate` { room, candidate }
- `audio-offer` { room, ... }
- `typing` { room }
- `stop-typing` { room }

## Run
```bash
flutter pub get
flutter run
```
