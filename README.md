# Martin

A native macOS menu bar notepad for standups and team meetings. Take notes from the menu bar or from the calendar, and Martin opens the Markdown note for that meeting, named after the event, with its attendees. Each calendar occurrence has one note, so coming back to a meeting reopens what you wrote.

## Build

Requires macOS 26 or newer, Xcode and an Apple Development signing certificate.

```sh
git config core.hooksPath .githooks
./scripts/build-app.sh
open build/Martin.app
```

## Calendar

**Take Notes** opens the note for the calendar event in progress, or a fresh note when nothing is on. **Upcoming Meetings…** in the menu shows today and the next three days; click a meeting to open its note. For Google Calendar, add the account in System Settings → Internet Accounts with Calendars turned on.

## Data

Each meeting is a folder in `~/Library/Application Support/Martin/meetings/` with `meeting.json` and `note.md`, which is the note you edit in Martin. A meeting taken from the calendar records its `occurrence`: the event's series identifier, shared by every occurrence of a recurring meeting, and that occurrence's original start.
