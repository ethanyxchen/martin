# Build Martin: a native macOS notetaker that keeps only what matters to me

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds. There is no PLANS.md in this repository; this file is the whole specification.


## Purpose / Big Picture

Martin is a personal meeting notetaker for one person (the owner, Ethan). Ordinary notetakers summarise the whole meeting and try to work out who said what; both are noisy. Martin does the opposite. It records a meeting from the laptop microphone, transcribes it live with Deepgram, and when the meeting ends it hands the transcript to a Claude agent that can look at the owner's real work in GitHub and Linear. The agent returns only the items that touch the owner's work: things the owner committed to, things asked of the owner, things the owner is waiting on, decisions that change the owner's work, and useful mentions. Each item quotes the exact words from the transcript with a timestamp and links the PR or ticket it relates to, so every claim can be checked in seconds. The owner reviews items in a small native window and accepts or rejects each one.

After this plan is complete, the owner can click a menu bar icon, press Record at the start of an in-person meeting with the laptop on the table, press Stop at the end, and within a minute or two see a short list of personal, sourced items for that meeting. The calendar event that was happening is attached automatically, and items still open from earlier meetings with the same people are shown and checked for completion.

Who said what is never used. The app does not attempt speaker diarization (automatically labelling which voice belongs to which speaker), because it is unreliable in a room with one microphone. Relevance is decided purely from content plus the owner's work context.


## Progress

- [ ] Milestone 1: analyzer command-line program produces sourced items from a sample transcript.
- [ ] Milestone 2: MartinKit library streams microphone audio to Deepgram and stores the transcript in SQLite.
- [ ] Milestone 3: menu bar app records a real meeting and shows its live transcript.
- [ ] Milestone 4: stopping a recording runs the analyzer and shows items in a review window with accept and reject.
- [ ] Milestone 5: calendar event and attendees attached automatically; Deepgram is primed with key terms.
- [ ] Milestone 6: open items from earlier meetings are carried forward and checked for completion.


## Surprises & Discoveries

None yet.


## Decision Log

- Decision: Native Swift app for capture, storage and UI; a small TypeScript program (the "analyzer") only for the Claude agent step.
  Rationale: The owner wants a native app, and Swift gives the best audio capture and the easiest route to real-time features later. The Claude Agent SDK only exists for TypeScript and Python, and it handles the agent loop and connections to remote MCP servers for us. Making the analyzer a one-shot program (JSON in on standard input, JSON out on standard output, then exit) keeps the boundary between the two languages as small as a function call.
  Date: 2026-10-19

- Decision: Post-meeting processing only for now, but transcription is streamed live during the meeting.
  Rationale: Streaming costs the same as uploading a file afterwards, nothing is lost if the app crashes mid-meeting, and a real-time feature later is just another reader of the same live transcript.
  Date: 2026-10-19

- Decision: No speaker diarization; relevance is decided from content and work context only.
  Rationale: Most of the owner's meetings are in person with a single laptop microphone, where diarization is unreliable. A later improvement (out of scope) is verifying only the owner's own voice against a short enrolled sample, which is a much easier problem.
  Date: 2026-10-19

- Decision: No stored knowledge base. The agent queries GitHub and Linear live through MCP when it analyses a meeting.
  Rationale: An indexed copy of the owner's work would go stale and need syncing. Computing context on demand means there is one source of truth for each piece of data.
  Date: 2026-10-19

- Decision: Google Calendar is read through Apple's EventKit, not the Google API.
  Rationale: When the Google account is added to macOS Calendar, EventKit returns its events, attendees and notes locally with a single permission prompt and no OAuth code in Martin.
  Date: 2026-10-19

- Decision: Apple voice processing (echo cancellation) is off for microphone capture.
  Rationale: Voice processing is tuned for one near speaker and suppresses distant voices, which is the opposite of what an in-person meeting with a laptop on the table needs.
  Date: 2026-10-19

- Decision: The raw audio is kept as a compressed file next to the database.
  Rationale: The audio cannot be recomputed. Keeping it lets us re-transcribe old meetings when the pipeline improves (for example, when voice verification lands).
  Date: 2026-10-19

- Decision: The item format is defined once in `schema/items.schema.json`. The analyzer passes it to the agent as the required output shape, and both sides test against the same example file `schema/items.example.json`.
  Rationale: Avoids the format silently drifting between the TypeScript and Swift halves.
  Date: 2026-10-19

- Decision: Slack, system audio capture for online calls, voice verification, and real-time nudges are out of scope for this plan.
  Rationale: Most meetings are in person; GitHub and Linear cover the core work context; the post-meeting flow must prove itself on real meetings first.
  Date: 2026-10-19


- Decision: The analyzer returns the finished markdown note, not structured items. The note (`note.md`) is the single source of truth, edited by the owner in a small text editor window; open items are unchecked `- [ ]` lines.
  Rationale: The owner wants the UI to be a small text editor showing action items at the end of the meeting. Rendering in the analyzer means the item format lives only in TypeScript, so there is nothing to duplicate in Swift and no `item` table or accept/reject state.
  Date: 2026-10-19

- Decision: Plain files instead of SQLite. Each meeting is a folder `~/Library/Application Support/Martin/meetings/<yyyy-MM-dd-HHmmss>/` with `meeting.json`, `transcript.jsonl`, the audio file, `note.md`, and `error.txt` when analysis failed. Analysis state is derived from which files exist.
  Rationale: Fewer moving parts, no dependency, and the notes are readable and greppable outside the app.
  Date: 2026-10-19

- Decision: Connectors are generic remote MCP servers configured in a Settings window (name, URL, token, enabled), with GitHub, Linear and Slack as presets. Tokens and the Deepgram and Anthropic keys are stored in the macOS Keychain; everything else in `settings.json`. The analyzer has a `check` mode that connects to each server and counts its tools, so Settings can show a live status.
  Rationale: The owner asked for the non-note UI to be about MCP connectors; a hand-edited config file is replaced by that UI.
  Date: 2026-10-19

- Decision: UX follows Wispr Flow (a small floating recording pill), Granola (a calm, typographic notes document) and Goodmeet (the owner's work app). There is no meeting library window; recent meetings are listed in the menu bar.
  Rationale: Owner direction.
  Date: 2026-10-19

- Decision: Work is split across three parallel agents against fixed contracts committed first: analyzer (TypeScript), capture core (Microphone, DeepgramStream, CalendarLookup), and the SwiftUI app.
  Rationale: Get to an MVP faster.
  Date: 2026-10-19

## Outcomes & Retrospective

Not started.


## Context and Orientation

The repository at `/Users/ethanchen/Developer/martin` is empty when this plan starts. Everything below is created by this plan. The final layout is:

    martin/
      plans/0001-post-meeting-personal-notetaker.md   this file
      schema/items.schema.json                        the one definition of an item
      schema/items.example.json                       a valid example, used by tests on both sides
      analyzer/                                       TypeScript, run with Bun
        package.json
        src/main.ts                                   reads input JSON, runs the agent, prints items JSON
        src/prompt.ts                                 builds the system prompt and user prompt
        src/main.test.ts
        fixtures/standup.json                         a hand-written sample meeting input
      app/                                            Swift
        project.yml                                   XcodeGen description of the Xcode project
        Package.swift                                 the MartinKit Swift package
        Sources/MartinKit/...                         audio, Deepgram, storage, analyzer runner, calendar
        Tests/MartinKitTests/...
        Martin/...                                    the SwiftUI menu bar app

Terms used in this plan:

Deepgram is a hosted speech-to-text service. Its streaming endpoint is a WebSocket (a long-lived two-way network connection) at `wss://api.deepgram.com/v1/listen`. The client sends raw audio bytes; Deepgram sends back JSON messages with transcribed text. The model used is `nova-3`.

Key terms (Deepgram calls them "keyterms") are words given to Deepgram up front so it recognises them reliably, such as the owner's name, teammates' names, repository names and ticket IDs. They are passed as repeated `keyterm=` query parameters, at most 500 tokens in total; aim for 20 to 50 terms. Passing them comma-separated silently does nothing.

The Claude Agent SDK is the npm package `@anthropic-ai/claude-agent-sdk`. Its `query({ prompt, options })` function runs Claude in a loop where it can call tools, and yields messages; the final message has `type: "result"`. When `options.outputFormat` is `{ type: "json_schema", schema }`, the result message carries the validated object in `structured_output` and has `subtype: "success"`; if Claude cannot produce valid output the subtype is `error_max_structured_output_retries`.

MCP (Model Context Protocol) is a standard way to give an agent tools. A remote MCP server is a web URL the agent connects to. This plan uses two: GitHub at `https://api.githubcopilot.com/mcp/` and Linear at `https://mcp.linear.app/mcp`. Both accept a personal token in an `Authorization: Bearer <token>` header, which avoids interactive sign-in flows.

SQLite is a database stored in a single file. GRDB is a Swift library for using SQLite. EventKit is Apple's framework for reading the user's calendars. AVAudioEngine is Apple's framework for capturing microphone audio. XcodeGen is a command-line tool that generates an Xcode project from a short `project.yml` text file, so the hard-to-read Xcode project file is never edited by hand.

An "item" is one thing Martin surfaces from a meeting. Its kinds are:

    commitment   the owner said they would do something
    request      someone asked the owner for something
    waiting_on   someone else will do something the owner depends on
    decision     something was decided that changes the owner's work
    mention      the owner's work was discussed and is worth knowing about

Configuration and secrets live in one file, `~/.config/martin/config.json`, which the owner creates by hand and which is never committed:

    {
      "name": "Ethan",
      "aliases": ["Ethan", "Ethan Chen", "E"],
      "github": "ethanchen",
      "keyterms": ["Martin", "Deepgram"],
      "deepgramApiKey": "...",
      "anthropicApiKey": "...",
      "githubToken": "...",
      "linearApiKey": "..."
    }

The GitHub token should be a fine-grained personal access token with read access to the owner's repositories. The Linear key should be a personal API key with only the Read permission. Martin only reads; it never writes to GitHub or Linear.

Data lives in `~/Library/Application Support/Martin/`: `martin.sqlite` for the database and `audio/<meeting id>.m4a` for recordings.


## Plan of Work

The work is ordered so each milestone runs and can be checked on its own. The analyzer comes first because whether the relevance matching works is the biggest unknown, and it can be tested with a written-out transcript and no audio at all.


### Milestone 1: the analyzer

At the end of this milestone, running the analyzer on a sample meeting prints a JSON list of items that cite transcript quotes and real GitHub or Linear links.

Create `schema/items.schema.json`, a JSON Schema for the object `{ "items": [Item] }`. Each Item has: `kind` (one of the five kinds above), `title` (a short imperative or headline, at most 100 characters), `detail` (one or two sentences of context), `quote` (verbatim words copied from the transcript), `at` (seconds from the start of the meeting where the quote begins, a number), `confidence` (`"high"` or `"maybe"`), and `links` (an array of `{ "label": string, "url": string }`, possibly empty). All fields are required and no extra properties are allowed. Write `schema/items.example.json` containing two valid items.

Create `analyzer/` with `bun init`, add `@anthropic-ai/claude-agent-sdk` as a dependency, and write `analyzer/src/main.ts`. It reads one JSON object from standard input, `AnalyzerInput`, calls `analyze(input)`, and writes the result to standard output as JSON. Errors go to standard error with a non-zero exit code. Secrets come from environment variables `ANTHROPIC_API_KEY`, `GITHUB_TOKEN` and `LINEAR_API_KEY`; the Swift app sets these when it starts the analyzer.

`analyze` calls `query` with these options: `model: "claude-opus-5-5"`; `systemPrompt` built by `src/prompt.ts`; `outputFormat: { type: "json_schema", schema }` where schema is imported from `../schema/items.schema.json`; `settingSources: []` so none of the owner's personal Claude Code settings leak in; `mcpServers` with `github` (`type: "http"`, the GitHub URL, the Bearer header) and `linear` (same shape); `allowedTools: ["mcp__github__*", "mcp__linear__*"]` and `permissionMode: "dontAsk"`, so the agent can use the MCP tools without prompts and is denied every other tool, such as running shell commands or editing files. It returns `structured_output` from the success result and throws otherwise.

The system prompt in `src/prompt.ts` says, in substance: You extract only what matters to the owner, named here with their aliases and GitHub username. First, use the tools to learn what the owner is currently working on: their open and recently merged pull requests and recent commits in the last 14 days, and their assigned and recently updated Linear issues. Then read the transcript and return only items that touch that work or that are addressed to the owner by name. Do not guess who is speaking from voice; use only words, such as "Ethan, can you", or a first-person "I'll" next to the owner's topic. Copy quotes exactly. Prefer fewer, correct items; when unsure, use confidence "maybe". Link the specific PR or issue whenever one matches. If nothing in the meeting concerns the owner, return an empty list.

The user prompt contains the meeting title, start time, attendees (if any), and the transcript rendered one line per segment as `[mm:ss] text`, so the model can read off `at` values.

Write `analyzer/fixtures/standup.json`: a realistic ten-minute standup transcript of about 40 segments that mentions one real open PR or Linear issue of the owner's (fill in after checking GitHub), includes a request to the owner by name, a commitment phrased in the first person about the owner's area, and plenty of irrelevant talk about other people's work.

Write `analyzer/src/main.test.ts` with `bun test`. It must not call the network. It checks that `schema/items.example.json` validates against the schema (use the `ajv` package as a dev dependency) and that the prompt renders timestamps correctly (segment at 75.4 seconds becomes `[01:15]`).

Proof: `bun test` passes, and running the analyzer on the fixture prints items. Then check whether the result can be compiled into a single executable with `bun build --compile` and still run. The Agent SDK starts a bundled Claude Code process internally, so compiling may break it. If the compiled binary fails, record it in Surprises & Discoveries and use the fallback decided there: the Swift app runs `bun run <repo>/analyzer/src/main.ts`, with the repository path stored in the config file as `"analyzerDir"`. Either result is acceptable; record which one was taken.


### Milestone 2: MartinKit, audio to transcript to database

At the end of this milestone, a Swift test proves Deepgram messages are parsed and stored correctly, and a small command-line target records 20 seconds of microphone audio and prints the live transcript.

Create `app/Package.swift` defining a library `MartinKit` (macOS 15 or later) with a dependency on GRDB, a test target `MartinKitTests`, and an executable target `martin-listen` used only for this milestone's manual check.

In `Sources/MartinKit/Config.swift`, define `struct Config: Decodable` that matches the config file above, and `static func load() throws -> Config` that reads `~/.config/martin/config.json`.

In `Sources/MartinKit/Microphone.swift`, define `final class Microphone` with `func start(onChunk: @escaping (Data) -> Void) throws`, plus `stop()`. It installs a tap on `AVAudioEngine.inputNode` and converts each buffer with `AVAudioConverter` to 16 kHz, mono, 16-bit signed little-endian samples (Deepgram calls this format `linear16`). It also writes the original buffers to an `AVAudioFile` in AAC format at the path it is given. Voice processing stays off (see Decision Log).

In `Sources/MartinKit/Deepgram.swift`, define `final class DeepgramStream` with `init(apiKey:keyterms:)`, `func connect(onSegment: @escaping (Segment) -> Void)`, `func send(_ audio: Data)`, and `func finish() async`. The URL is `wss://api.deepgram.com/v1/listen?model=nova-3&encoding=linear16&sample_rate=16000&channels=1&smart_format=true&interim_results=false` followed by one `&keyterm=<percent-encoded term>` per term. The header is `Authorization: Token <apiKey>`. Use `URLSessionWebSocketTask`. Messages with `"type": "Results"` and `"is_final": true` produce a `Segment(at: start, duration: duration, text: channel.alternatives[0].transcript)`; empty transcripts are skipped. Send `{"type":"KeepAlive"}` every 5 seconds when no audio is flowing. `finish()` sends `{"type":"CloseStream"}` and waits for the socket to close so the final words are not lost. Keep the parsing in a pure function `static func segment(from json: Data) -> Segment?` so it can be tested without a network.

In `Sources/MartinKit/Store.swift`, open `~/Library/Application Support/Martin/martin.sqlite` with GRDB (tests use an in-memory database) and migrate this schema:

    meeting(id TEXT PRIMARY KEY, startedAt DATETIME, endedAt DATETIME NULL,
            title TEXT NULL, attendees TEXT NULL, calendarEventId TEXT NULL,
            analysis TEXT NOT NULL DEFAULT 'pending')      -- pending, running, done, failed
    segment(meetingId TEXT REFERENCES meeting ON DELETE CASCADE,
            at REAL, duration REAL, text TEXT)
    item(id TEXT PRIMARY KEY, meetingId TEXT REFERENCES meeting ON DELETE CASCADE,
         kind TEXT, title TEXT, detail TEXT, quote TEXT, at REAL,
         confidence TEXT, links TEXT, verdict TEXT NULL)   -- verdict: NULL, accepted, rejected

`attendees` and `links` are JSON text. The duration of a meeting is not stored; it is computed from `startedAt` and `endedAt`.

Tests in `Tests/MartinKitTests/`: `DeepgramTests` feeds a recorded final Results message, an interim one and an empty one into `segment(from:)` and checks only the first yields a segment. `StoreTests` inserts a meeting with segments and items and reads them back. `SchemaContractTests` decodes `schema/items.example.json` into the Swift `Item` type, proving Swift agrees with the shared schema.

`martin-listen` loads the config, starts the microphone and Deepgram stream, prints each segment as `[mm:ss] text`, and stops after 20 seconds.

Proof: `swift test` passes; `swift run martin-listen` shows your speech appearing as lines within a second or two of speaking. The first run will trigger the macOS microphone permission prompt for the terminal app.


### Milestone 3: the menu bar app

At the end of this milestone, the owner can record a real meeting from the menu bar and read its transcript afterwards.

Install XcodeGen (`brew install xcodegen`). Write `app/project.yml` describing one macOS application target `Martin` (bundle id `dev.ethanchen.martin`, deployment target macOS 15) that depends on the local `MartinKit` package. Set `LSUIElement` to true in its Info.plist so it lives only in the menu bar, and set `NSMicrophoneUsageDescription` to "Martin records meetings you choose to record." and `NSCalendarsFullAccessUsageDescription` to "Martin attaches the current calendar event to a recording." Generate the project with `xcodegen` and add `app/Martin.xcodeproj` to `.gitignore`, since it is generated.

In `app/Martin/`, create a SwiftUI `@main` app using `MenuBarExtra`. The menu shows Record when idle, and Stop with the elapsed time when recording, plus "Open Martin" and Quit. Put recording logic in `Sources/MartinKit/Recorder.swift`, an `@Observable` class that, on start, inserts a meeting row, starts `Microphone` and `DeepgramStream`, and inserts each segment into the store as it arrives. On stop, it finishes the stream, stops the microphone, and sets `endedAt`. The icon changes to a filled red circle while recording so it is obvious.

"Open Martin" opens a window with a list of meetings on the left (title or start time, and duration) and the selected meeting's transcript on the right as `[mm:ss] text` lines.

Proof: build and run from Xcode or with `xcodebuild -project app/Martin.xcodeproj -scheme Martin build`, then record a two-minute conversation, stop it, and see it in the window with its transcript and an `.m4a` file in `~/Library/Application Support/Martin/audio/`.


### Milestone 4: post-meeting analysis and review

At the end of this milestone, stopping a recording produces reviewed, sourced items.

In `Sources/MartinKit/Analyzer.swift`, define `struct Analyzer` with `func run(meeting: Meeting, segments: [Segment], config: Config) async throws -> [Item]`. It encodes `AnalyzerInput` (the same shape as `analyzer/src/main.ts` expects: owner profile from config, meeting title, start time, attendees, segments), starts the analyzer with `Process` (either the compiled binary or `bun run`, as decided in Milestone 1) with the secrets in its environment, writes the input to its standard input, and decodes standard output into `[Item]`. A non-zero exit throws an error containing the standard error text.

After `Recorder` stops, it sets `analysis` to `running`, runs the analyzer in the background, writes the items, and sets `analysis` to `done`, or `failed` with the error logged. A meeting whose analysis failed shows a Retry button. On app launch, any meeting left `running` (the app quit mid-analysis) is reset to `pending` and re-run.

The meeting window gains an Items section above the transcript, grouped by kind in the order commitment, request, waiting_on, decision, mention. "maybe" items are collapsed under "Maybe relevant". Each item shows title, detail, the quote with its timestamp (clicking the timestamp scrolls the transcript to that segment), links that open in the browser, and Accept and Reject buttons that set `verdict`. Rejected items are dimmed, not hidden. A macOS notification "N items from <title>" is posted when analysis finishes.

Add `AnalyzerTests` that runs a stub analyzer (a two-line shell script in the test bundle that prints `schema/items.example.json`) and checks the items are decoded and stored.

Proof: record a short mock meeting in which you say something like "Ethan, can you review the auth PR today?" referring to a real open PR of yours; within about two minutes of stopping, a notification appears and the review window shows a `request` item quoting that sentence and linking the PR.


### Milestone 5: calendar and key terms

At the end of this milestone, recordings are titled from the calendar and Deepgram recognises names and project terms reliably.

In `Sources/MartinKit/Calendar.swift`, request full calendar access with EventKit and define `func currentEvent(at: Date) -> CalendarEvent?`, which returns the event in progress (or starting within the next 10 minutes) that has attendees, preferring the one that started most recently. `CalendarEvent` holds id, title, attendee names, and notes. When recording starts, `Recorder` attaches it to the meeting. The menu bar shows "Recording: <title>". The owner must have added the Google account in System Settings → Internet Accounts with Calendars enabled.

Key terms sent to Deepgram are computed at record start: the config `keyterms`, the owner's aliases, and the first names and full names of the event's attendees, de-duplicated and capped at 50 terms. The meeting notes are passed to the analyzer as additional context, because agendas often name the projects discussed.

Proof: with a calendar event in progress, start recording; the meeting is titled with the event name, and saying an attendee's unusual name is transcribed correctly.


### Milestone 6: carry open items forward

At the end of this milestone, Martin remembers what is still open across meetings.

An open item is an accepted `commitment`, `request` or `waiting_on` item whose meeting is earlier than the current one and which has not been marked done. Add a nullable `doneAt DATETIME` column to `item`. When analysing a meeting, the app includes open items from earlier meetings that share at least one attendee (or all open items, if the meeting has no attendees) in `AnalyzerInput.open`, each with its id. The analyzer's schema gains a top-level `resolved` array of `{ "id": string, "evidence": string, "url": string }`. The prompt instructs the agent to mark an open item resolved only when GitHub or Linear shows it done (merged PR, closed issue) or the transcript says so, and to cite that evidence. The app sets `doneAt` for resolved items. The meeting view shows a "Still open" section listing remaining open items, with a manual "Done" button.

Proof: after a meeting where you commit to a task, complete it in GitHub (merge the PR), then analyse another meeting with an overlapping attendee; the earlier commitment appears as resolved, with a link to the merged PR.


## Concrete Steps

All commands run from `/Users/ethanchen/Developer/martin` unless stated.

One-time setup:

    git init
    printf '.env\napp/Martin.xcodeproj\n.build/\nnode_modules/\nanalyzer/dist/\n' > .gitignore
    brew install xcodegen
    mkdir -p ~/.config/martin   # then write config.json as described in Context and Orientation

Milestone 1:

    cd analyzer && bun init -y && bun add @anthropic-ai/claude-agent-sdk && bun add -d ajv
    bun test
    ANTHROPIC_API_KEY=... GITHUB_TOKEN=... LINEAR_API_KEY=... bun run src/main.ts < fixtures/standup.json
    bun build --compile src/main.ts --outfile dist/martin-analyzer
    ./dist/martin-analyzer < fixtures/standup.json

Expected output shape (values will differ):

    {"items":[{"kind":"request","title":"Review the auth PR today","detail":"Asked during standup to review before the release cut.",
      "quote":"Ethan, can you take a look at the auth PR today","at":312.4,"confidence":"high",
      "links":[{"label":"PR #412","url":"https://github.com/..."}]}]}

Milestone 2:

    cd app && swift test
    cd app && swift run martin-listen

Milestone 3 and later:

    cd app && xcodegen && xcodebuild -project Martin.xcodeproj -scheme Martin build


## Validation and Acceptance

The plan is complete when all of these hold on the owner's Mac. `bun test` in `analyzer/` and `swift test` in `app/` pass. A real in-person meeting of at least 15 minutes, recorded with the laptop on the table, produces a transcript in the Martin window and, within a few minutes of stopping, a notification and a list of items. Every item's quote appears verbatim in the transcript at its timestamp. At least the owner's direct requests and first-person commitments are found, and items about other people's work are absent or marked "maybe". The meeting is titled from the calendar. In a later meeting, an earlier commitment whose PR has since merged is shown as resolved.

The quality bar is judged by the owner on five real meetings. Record each meeting's precision (accepted items divided by all items) in Outcomes & Retrospective; prompt changes should be driven by the rejected items.


## Idempotence and Recovery

Every step can be re-run. Database migrations use GRDB's `DatabaseMigrator`, which only applies migrations not yet applied. Re-running analysis on a meeting deletes that meeting's existing items first, so items never duplicate; verdicts on deleted items are lost, which is acceptable because re-analysis is an explicit action. If Deepgram disconnects mid-meeting, the microphone keeps writing the `.m4a` file; `Recorder` reconnects and continues, and the gap is visible in the transcript. To start over completely, quit Martin and delete `~/Library/Application Support/Martin/`.


## Artifacts and Notes

A final Deepgram streaming message looks like this (trimmed); only `type`, `is_final`, `start`, `duration` and `channel.alternatives[0].transcript` are used:

    {"type":"Results","is_final":true,"start":312.4,"duration":3.1,
     "channel":{"alternatives":[{"transcript":"Ethan, can you take a look at the auth PR today","confidence":0.97}]}}

The Agent SDK result handling, in essence:

    for await (const message of query({ prompt, options })) {
      if (message.type !== "result") continue
      if (message.subtype === "success" && message.structured_output) return message.structured_output
      throw new Error(`analysis failed: ${message.subtype}`)
    }


## Interfaces and Dependencies

Dependencies: Bun (TypeScript runtime and test runner), `@anthropic-ai/claude-agent-sdk`, `ajv` (tests only), Swift 6 with Xcode, GRDB (Swift SQLite), XcodeGen, and Apple frameworks AVFoundation, EventKit, UserNotifications and SwiftUI. Hosted services: Deepgram (`nova-3` streaming), the Anthropic API (model `claude-opus-5-5`), GitHub remote MCP, and Linear remote MCP.

In `analyzer/src/main.ts`:

    type Segment = { at: number; text: string }
    type AnalyzerInput = {
      owner: { name: string; aliases: string[]; github: string }
      meeting: { title: string | null; startedAt: string; attendees: string[]; notes: string | null }
      segments: Segment[]
      open: { id: string; kind: string; title: string; quote: string; meetingTitle: string | null }[]
    }
    export async function analyze(input: AnalyzerInput): Promise<{ items: Item[]; resolved: Resolved[] }>

`open` is an empty array and `resolved` is absent from the schema until Milestone 6.

In `app/Sources/MartinKit/`:

    struct Config: Decodable { name, aliases, github, keyterms, deepgramApiKey, anthropicApiKey, githubToken, linearApiKey }
    struct Segment: Codable { var at: Double; var duration: Double; var text: String }
    struct Item: Codable, Identifiable { id, kind, title, detail, quote, at, confidence, links, verdict, doneAt }
    final class Microphone { func start(writingTo: URL, onChunk: @escaping (Data) -> Void) throws; func stop() }
    final class DeepgramStream { init(apiKey: String, keyterms: [String]); func connect(onSegment: @escaping (Segment) -> Void); func send(_: Data); func finish() async; static func segment(from: Data) -> Segment? }
    final class Store { init(path: URL?) throws }   // nil path means in-memory, for tests
    @Observable final class Recorder { func start() throws; func stop() async }
    struct Analyzer { func run(meeting: Meeting, segments: [Segment], open: [Item], config: Config) async throws -> Analysis }
    func currentEvent(at: Date) -> CalendarEvent?


Revision note (2026-10-19): Design revised after owner feedback. The review UI became a markdown text editor rendered by the analyzer, storage moved from SQLite to per-meeting folders, the config file was replaced by a connectors Settings UI with Keychain secrets, and the Milestone 4 accept/reject review and Milestone 6 item table are superseded by checkbox lines in `note.md`. Milestones 1 to 5 are being built in parallel; Milestone 6 (carry forward) remains.
