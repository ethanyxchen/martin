# Martin

A native macOS menu bar assistant for standups and team meetings that keeps only what concerns you. When you start recording, Martin lists the pull requests you merged and moved forward since the last time this meeting met, so you know what to share. While the team talks, it matches the live transcript against your recent pull requests and the topics you follow, and jots very brief bullets of your to-dos, decisions and open questions. When you stop, the result is saved as the meeting's note.

## Build

Requires macOS 26 or newer, Xcode, [Bun](https://bun.sh) and an Apple Development signing certificate.

```sh
brew install oven-sh/bun/bun
git config core.hooksPath .githooks
./scripts/build-app.sh
open build/Martin.app
```

The build compiles the analyzer in `analyzer/` and bundles it into the app.

## Set up

Open **Settings…** from the menu bar icon.

**Keys.** Paste a [Deepgram](https://deepgram.com) API key; Deepgram transcribes the room while you record. Notes are written with your Claude Code sign-in.

**You.** Your name, what people call you, and the teammates, projects and topics you follow. The transcript listens for these words, and Martin treats them as your interests.

**Connectors.** Martin reads your pull requests through [GitHub CLI](https://cli.github.com) and never writes:

```sh
brew install gh
gh auth login
```

**Calendar.** Martin names a recording after the calendar event in progress, and finds the last time a recurring meeting met to know what is new since then. For Google Calendar, add the account in System Settings → Internet Accounts with Calendars turned on.

## Data

Each meeting is a folder in `~/Library/Application Support/Martin/meetings/` with the audio, the transcript, and `note.md`, which is the note you edit in Martin.
