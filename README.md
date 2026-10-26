# Martin

A native macOS menu bar notepad for standups and team meetings. Start a meeting from the menu bar or from the calendar, and Martin opens a Markdown note named after the event, with its attendees.

## Build

Requires macOS 26 or newer, Xcode and an Apple Development signing certificate.

```sh
git config core.hooksPath .githooks
./scripts/build-app.sh
open build/Martin.app
```

## Calendar

**New Meeting** names the note after the calendar event in progress. **Upcoming Meetings…** in the menu shows today and the next three days; click a meeting to start its note. For Google Calendar, add the account in System Settings → Internet Accounts with Calendars turned on.

## Data

Each meeting is a folder in `~/Library/Application Support/Martin/meetings/` with `meeting.json` and `note.md`, which is the note you edit in Martin.
