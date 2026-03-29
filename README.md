# RedFlag

RedFlag is an iOS AR graffiti prototype built with SwiftUI, ARKit, RealityKit, and an embedded Unity export. The app connects to a local backend to sync poster rooms, live drawing strokes, stickers, territory ownership, and poster audio.

## What The App Does

- Shows a stylized native iOS shell for login, team selection, poster browsing, and remote editing.
- Opens a Unity-powered AR poster view for tracked poster interactions.
- Lets players draw strokes, place stickers/GIFs, and attach or trigger poster audio.
- Syncs poster state with a backend over REST and Socket.IO-style realtime events.

## Main Tech

- SwiftUI for the native interface
- ARKit and RealityKit for iOS AR support
- Embedded Unity export for the tracked poster scene
- Local backend API for auth, teams, posters, stickers, canvas state, territory, and audio

## Project Layout

- `itechARapp/`: native iOS app source
- `itechARapp.xcodeproj/`: main Xcode project
- `BetterVersion/`: Unity iOS export and related Xcode project files
- `patch_face_tracking.sh`: reapplies the Unity face-tracking stub patch after a fresh export
- `itechARappTests/`, `itechARappUITests/`: test targets

## Backend Notes

The app expects a backend server on port `3000`.

- On simulator, the default route is `http://127.0.0.1:3000`
- The backend route can be changed inside the app from the `BACKEND ROUTE` panel

Expected backend features include:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/teams`
- `POST /api/teams`
- `POST /api/teams/{teamId}/join`
- `GET /api/posters`
- `GET /api/posters/{posterId}/canvas`
- `GET /api/posters/{posterId}/territory`
- `GET /api/stickers/library`
- poster audio endpoints under `/api/posters/{posterId}/audio`

## Source Control Notes

This repository is intentionally set up as a source-only export.

Ignored content includes:

- Xcode user state and build outputs
- local backup folders
- Unity runtime data blobs
- IL2CPP generated compile outputs and temp artifacts
- compiled Unity framework/runtime binaries

That keeps the repo focused on the editable Xcode and Unity project files instead of generated output.

## Running The App

1. Open `itechARapp.xcodeproj` in Xcode.
2. Make sure the backend server is running and reachable from the chosen simulator/device.
3. Build and run the `itechARapp` scheme.
4. Use the backend route panel in the app if the server address changes.

## Current Status

Recent client fixes include:

- more tolerant poster parsing for backend payload variations
- fallback handling for backend route changes
- remote editor access even when poster sync fails
- stroke payload color aliases to improve backend template compatibility
