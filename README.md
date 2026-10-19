# Martin

A native macOS menu bar notetaker that keeps only what concerns you. Record a meeting, and when it ends Martin reads the transcript against your own work in GitHub, Linear and other connectors, then writes a short note of your to-dos, what you are waiting on, decisions and things worth knowing. Each item quotes the transcript with a timestamp.

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

**You.** Your name, what people call you, and words the transcript should get right, such as teammates and project names.

**Connectors.** Martin holds no credentials for your work tools. It reads them through tools you have already signed in to, and only ever reads.

- **GitHub** through [GitHub CLI](https://cli.github.com), limited to read-only commands:

  ```sh
  brew install gh
  gh auth login
  ```

- **Linear, Slack, Notion, Google Drive and others** through your [Claude connectors](https://claude.ai/settings/connectors). Connect them once in Claude; Martin uses only the tools each connector marks as read-only.

Settings shows each source and whether it is connected.

**Calendar.** Martin names a recording after the calendar event in progress. For Google Calendar, add the account in System Settings → Internet Accounts with Calendars turned on.

## Data

Each meeting is a folder in `~/Library/Application Support/Martin/meetings/` with the audio, the transcript, and `note.md`, which is the note you edit in Martin.
