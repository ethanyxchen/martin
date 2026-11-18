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

## Project overviews

Each project page can show an overview of the project: what you're working on **Now**, what comes **Next**, and what you've **Shelved**. Martin builds it from the project's notes and, when a GitHub repository is linked, from its commits, branches and pull requests.

To turn it on, choose Claude or OpenAI in Settings and paste an API key. The key is kept in your Mac's Keychain. Martin's bundled agent sends the provider the project's name, the notes it chooses to read, the repository's recent activity and your git name, email and GitHub login. Nothing is sent while no key is saved.

Every 30 minutes Martin checks each project and refreshes its overview only when something changed: a note was edited, added or removed, the repository link changed, or the repository has new commits or pull request updates. Choose **Refresh Overview** from the project's menu, or Refresh in the section, to update it now. When a refresh fails, the last overview stays and the reason shows above it; Martin tries again at the next check, or you can choose Try Again.

## Calendars

Martin reads the calendars you've added to macOS. To use Google Calendar, add your account in System Settings → Internet Accounts with Calendars turned on. In Settings, untick any calendars you don't want Martin to follow.

## Syncing across Macs

Sign in with Apple in Settings to keep your notes, meetings, projects and images in sync on every Mac you sign in on. Martin syncs every minute and whenever you change something. When a note is edited on two Macs before they sync, the later edit wins. A project's linked repository, its overview and repository suggestions stay on each Mac. Signing out keeps your notes on the Mac and stops syncing.

## Your data

Until you sign in, everything stays on your Mac. Signed in, Martin keeps a copy in its Supabase database, readable only by your account. Each meeting is a folder in `~/Library/Application Support/Martin/meetings/` holding `note.md`, the note itself, and `meeting.json`, the event it belongs to. Projects are in `projects.json`, and their overviews in `overviews.json`. Mentions are saved in the note as `@{Ada Lovelace <ada@example.com>}`, so plain-text search finds every note that mentions someone.

## Building from source

You need Xcode and an Apple Development signing certificate.

```sh
git config core.hooksPath .githooks
./scripts/build-app.sh
open build/Martin.app
```

Run the tests with `swift test --package-path app`.

Syncing needs a Supabase project with Sign in with Apple turned on, `martin://auth` in its redirect URLs and the schema in `supabase/migrations` applied. Pass the project to the build as `SUPABASE_URL` and `SUPABASE_KEY` (the publishable key), either in the environment or as lines in the main checkout's `.env`. Builds without them hide the Account section.

## Releasing

Tag `main` with the next version and push the tag. Each release raises the last number of the latest version tag by 2, so `v1.1.0` is followed by `v1.1.2`, then `v1.1.4`.

```sh
git tag -a v1.1.2 -m v1.1.2
git push origin v1.1.2
```

The Release workflow builds Martin, signs it with Developer ID, notarizes the app and the DMG, signs the update for Sparkle and publishes `Martin-<version>.dmg` and `appcast.xml` to a GitHub release. Installed copies find the update through the appcast of the latest release.
