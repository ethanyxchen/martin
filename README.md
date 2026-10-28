# Martin

A menu bar notepad for macOS, made for standups and team meetings. Click **Take Notes** and Martin opens a Markdown note for the meeting on your calendar, named after the event. Every occurrence of a meeting has its own note, so coming back to a meeting brings back what you wrote.

## Install

Martin needs macOS 26 or newer.

1. Download the latest `.dmg` from [Releases](https://github.com/ethanyxchen/martin/releases/latest).
2. Open it and drag **Martin** into **Applications**.
3. Open Martin from Applications. It lives in the menu bar.

When a new version is out, Martin lets you know.

## Taking notes

- **Take Notes** opens the note for the meeting happening now, or a blank note when nothing is on.
- **Upcoming Meetings…** shows today and the next three days. Click a meeting to open its note.
- **Recent** in the menu reopens your latest notes.

Notes are Markdown. Use the Format menu or the usual shortcuts for bold (⌘B), italic (⌘I), strikethrough (⇧⌘X), code (⇧⌘C) and links (⌘K).

## Mentions

Type `@` to mention someone. Martin suggests the meeting's guests first, then people from your earlier meetings, and matches on names and emails. Press Return or Tab to pick one.

## Finding notes

- **Notes** lists every note, newest first.
- **Meetings** groups notes by recurring meeting. Click one to see all its notes. One-off meetings and notes without an event are under **Other notes**.
- **Archive** (⇧⌘A) keeps notes you've put away without deleting them.

Choose which pages appear in the navigation bar in Settings.

## Calendars

Martin reads the calendars you've added to macOS. To use Google Calendar, add your account in System Settings → Internet Accounts with Calendars turned on. In Settings, untick any calendars you don't want Martin to follow.

## Your data

Everything stays on your Mac. Each meeting is a folder in `~/Library/Application Support/Martin/meetings/` holding `note.md`, the note itself, and `meeting.json`, the event it belongs to. Mentions are saved in the note as `@{Ada Lovelace <ada@example.com>}`, so plain-text search finds every note that mentions someone.

## Building from source

You need Xcode and an Apple Development signing certificate.

```sh
git config core.hooksPath .githooks
./scripts/build-app.sh
open build/Martin.app
```

Run the tests with `swift test --package-path app`.

## Releasing

Push a version tag such as `v0.1.0`. The Release workflow builds Martin, signs it with Developer ID, notarizes the app and the DMG, signs the update for Sparkle and publishes `Martin-<version>.dmg` and `appcast.xml` to a GitHub release. Installed copies find the update through the appcast of the latest release.
