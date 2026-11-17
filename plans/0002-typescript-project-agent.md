# Build martin-agent: a bundled TypeScript agent on the Claude and OpenAI APIs

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.


## What we are building

A small TypeScript program, `martin-agent`, that ships inside `Martin.app` and makes every model call Martin needs. It runs two jobs:

- an overview job, which reads a project's notes and its repository's recent activity and returns what the person is working on now, what comes next and what they have shelved;
- a repository lookup job, which picks the GitHub repository that holds a project's code.

It talks to the Claude API or the OpenAI API with a key the user pastes into Settings, using each provider's official SDK and real tool calling.

In the app, each project page gets an Overview section with Now, Next and Shelved tasks. Every 30 minutes Martin checks each project and refreshes its overview only when something changed since the last one: a note edited, added or removed, the repository link, or new commits or pull request updates. Refresh Overview runs it on demand. Editing notes never starts a refresh by itself; the next check or a manual refresh picks the edit up.

When it's done: build with `./scripts/build-app.sh`, launch with `open -g -j build/Martin.app`, choose Claude or OpenAI in Settings and paste a key, open a project with notes, and choose Refresh Overview or wait for its next scheduled run.


## Architecture

    ┌──────────────────────────── Martin.app (Swift) ─────────────────────────────┐
    │                                                                              │
    │  Settings: provider (Claude | OpenAI) + API key ──► Keychain                 │
    │                                                                              │
    │  AppState                                                                    │
    │   ├─ repository lookup pass (at launch, unlinked projects) ─┐                │
    │   └─ overview pass (30-min check, if changed + manual) ─────┤                │
    │                                                             ▼                │
    │  AgentClient ── builds Job JSON (project, note paths, previous overview,     │
    │       │          repository folder)                                          │
    │       │  starts Contents/MacOS/martin-agent with ANTHROPIC_API_KEY or        │
    │       │  OPENAI_API_KEY in its environment, job on stdin                     │
    │       ▼                                                                      │
    │  ◄── stdout NDJSON: {"type":"progress",...}* then {"type":"result",...}      │
    │       │                                                                      │
    │       └─► lookups.json · overviews.json (beside projects.json)               │
    │           Project page: RepositoryCard · OverviewSection                     │
    └──────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
    ┌────────────────────── martin-agent (TypeScript, bun-compiled) ───────────────┐
    │  main.ts        read Job, pick job + provider, print events                  │
    │                                                                              │
    │  jobs/          provider-neutral: system prompt, tools, result schema        │
    │   ├─ overview.ts            → Overview  {now, next, shelved}                 │
    │   └─ repositoryLookup.ts    → {evidence, slugs}                              │
    │                                                                              │
    │  tools.ts       read-only, typed, scoped to the job                          │
    │   ├─ read_note(id, offset)  pages from paths named in the job                │
    │   └─ repo_activity(source)  paged commits, capped pull requests              │
    │                                                                              │
    │  providers/     the only files that import an SDK                            │
    │   ├─ anthropic.ts  @anthropic-ai/sdk tool runner + structured output         │
    │   └─ openai.ts     openai SDK Responses API tool loop + JSON schema output   │
    └──────────────────────────────────────────────────────────────────────────────┘
                     │                                   │
                     ▼                                   ▼
          api.anthropic.com/v1/messages        api.openai.com/v1/responses

Swift owns the data, the UI and the keys. The agent owns everything that talks to a model. They meet at one boundary: one process per job, the job as JSON on stdin, and events as newline-delimited JSON on stdout, ending in one result or error. Swift sends note paths, not note text; the model reads only the notes it chooses, and only those paths.


## Progress

- [x] (2026-11-16) Write this plan.
- [x] (2026-11-17) Apply review feedback and the product decision that refreshes run every 30 minutes or by manual command.
- [x] (2026-11-17) Skip unchanged projects at the 30-minute check; keep results from runs with mid-run edits; local today; drop `list_notes`; capped pull request listing; merge the benchmark into the evaluation.
- [ ] Milestone 0: prototypes (completed: Anthropic tool runner with structured output, OpenAI Responses tool loop with JSON schema output, `gpt-6-luna` confirmed; remaining: signed bun binary under the hardened runtime).
- [x] (2026-11-17) Milestone 1: agent package, tools, jobs, fake provider, tests (29 passing).
- [x] (2026-11-17) Milestone 2: Anthropic provider; live sample passes.
- [x] (2026-11-17) Milestone 3: OpenAI provider; live sample passes.
- [x] (2026-11-17) Evaluation runner and tracking fixtures from Milestone 6, brought forward for benchmarking: 22/22 checks on both providers.
- [x] (2026-11-17) Settings take a Claude or OpenAI API key, kept in the Keychain, in place of the Claude Code and Codex logins. `build-app.sh` bundles and signs `martin-agent`, which runs under the hardened runtime with no extra entitlements, and repository lookup runs its `repositoryLookup` job with the key in `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`. Remaining: `AgentClient`'s typed failures and cancellation.
- [ ] Milestone 4: bundle and sign the agent, Swift settings, keys, `AgentClient`, repository lookup on the agent.
- [ ] Milestone 5: overview storage, scheduled and manual refresh, request lifecycle and Overview section.
- [ ] Milestone 6: hook, CI, release and evaluation.


## Surprises & Discoveries

- Observation: Anthropic strict tools reject `minimum` and `maximum` on integer properties, which Zod's `.int().nonnegative()` emits.
  Evidence: `400 tools.0.custom: For 'integer' type, properties maximum, minimum are not supported`. `read_note`'s offset is now a plain number checked inside the tool.
- Observation: `client.beta.messages.toolRunner` accepts `output_config.format` and `fallbacks: "default"` together with tools; the model calls tools and then ends with schema-valid JSON. No `submit` tool is needed.
  Evidence: live sample run, 3 parallel `read_note` calls, then one valid result, 9 s.
- Observation: both providers pass the tracking fixtures chained and from scratch, and both page past character 4,000 of the retro note to find the completion update.
  Evidence: Claude 22/22, 44 s, $0.16 for five runs; OpenAI 22/22, 58 s. Stage 3 calls include `read_note({ id: "retro", offset: 4000 })` on both.
- Observation: the bun-compiled binary is 70 MB.

- Observation: `Command.run` currently returns nil for nonzero process exits, discarding stdout. Adding an environment parameter alone would hide the agent's error events.
  Evidence: `app/Sources/MartinKit/Command.swift`, `Run.settle()`, only passes output to its completion when the child exits successfully.
- Observation: repository lookup already rejects results after project deletion or an assistant change; overview requests need the same protection and must also handle overlapping refreshes and changed inputs.
  Evidence: `app/Martin/MartinApp.swift`, `suggestRepository(for:)`, compares `lookupRound` and checks that the project still exists before saving.
- Observation: note modification dates cannot determine whether repository activity, note membership or a repository link has changed.
  Evidence: notes can be moved or deleted independently of their text, and `Repository.activity(since:)` reads a separate source. The change check therefore compares note membership and the repository link with the inputs of the last successful overview and asks git and GitHub for activity since its `readAt`, in addition to note edit dates.


## Decision Log

- Decision: API keys and the providers' APIs, not the user's Claude Code or Codex login.
  Rationale: Real tool calling, structured output, prompt caching and refusal handling. No dependency on an installed, signed-in CLI.
  Date: 2026-11-16
- Decision: Support both Claude and OpenAI.
  Rationale: The user wants to keep a provider choice.
  Date: 2026-11-16
- Decision: TypeScript, compiled with `bun build --compile` into one executable at `Martin.app/Contents/MacOS/martin-agent`.
  Rationale: Both providers ship first-class TypeScript SDKs, and Swift has no official Anthropic SDK. One compiled executable needs no runtime on the user's Mac.
  Date: 2026-11-16
- Decision: One adapter per provider on its official SDK, behind a shared `Provider` interface, rather than a provider-neutral SDK.
  Rationale: Caching, effort, refusal fallbacks and strict schemas differ by provider. Prompts, tools and schemas are still written once.
  Date: 2026-11-16
- Decision: Overviews are stored in `overviews.json` beside `projects.json`, keyed by project id. Only Swift writes it.
  Rationale: One store, one writer, the same pattern as `lookups.json`. Each record holds the last successful overview, the notes and repository it was built from, and the last check time, which have different meanings.
  Date: 2026-11-16
- Decision: A project is checked 30 minutes after its previous check, including a skipped, failed or manual one. A project never checked is checked at the first scheduler pass. Manual refresh bypasses the time gate and the change check.
  Rationale: This is a product decision. Note edits, repository changes and request completion do not trigger extra checks. Persisting the check time prevents relaunches or failures from causing repeated automatic calls within the interval.
  Date: 2026-11-17
- Decision: A due check calls the model only when something changed since the last successful overview: a note edited after its `readAt`, a note added to or removed from the project, a changed repository link, or commits or pull request updates since `readAt`. A project with no successful overview always runs. A check whose git or GitHub query fails counts as changed.
  Rationale: Rerunning every eligible project every 30 minutes would cost roughly 48 Opus runs a day per project to reproduce the same overview. The check is local or two quick commands.
  Date: 2026-11-17
- Decision: At most one overview request runs per project. A result is saved only while its request is still the latest for the project, the project still exists and is eligible, and the credentials are unchanged. Edits made during a request do not discard its result. `readAt` is the request's input cutoff, not its completion time.
  Rationale: Because `readAt` is the cutoff, an edit made during a run is still newer than `readAt` and is picked up by the next check. Discarding such results would waste the call and, while someone is typing, keep the overview from ever updating.
  Date: 2026-11-17
- Decision: Today's date is derived from `cutoff` in the timezone offset it carries, and Swift writes `cutoff` in the user's local timezone.
  Rationale: Deriving it in UTC makes "today" tomorrow during US evenings and drops tasks dated today as future dates.
  Date: 2026-11-17
- Decision: The note list is sent only in the opening message; there is no `list_notes` tool.
  Rationale: The list is small and always needed, so a tool returning the same text duplicated it.
  Date: 2026-11-17
- Decision: Pull requests come from one fixed `gh pr list` call capped at 30, which says when the cap was reached. Commits keep cursor paging.
  Rationale: GraphQL cursor paging added a second client for little gain; a stated cap still never silently drops records.
  Date: 2026-11-17
- Decision: One script, `agent/eval/eval.ts`, runs both the tracking evaluation on fixtures with expectations and the retrospective over a real library without expectations. There is no separate benchmark.
  Rationale: Both replay chained overviews over a set of notes; two runners would duplicate that.
  Date: 2026-11-17
- Decision: Long notes and repository activity are available in bounded pages, and completed tasks leave the overview. Repository events provide project context; another contributor's activity alone does not establish that the user owns a task.
  Rationale: The model needs access to later evidence and explicit task-transition rules to keep an accurate overview of the person's work.
  Date: 2026-11-17
- Decision: Bundle and sign the executable in Milestone 4, before its first built-app acceptance check.
  Rationale: Swift integration cannot be verified in the app without the executable it launches.
  Date: 2026-11-17
- Decision: Models.
  - Claude overview: `claude-haiku-5-5` at effort `high` (changed from `claude-opus-5-5` on 2026-11-17 at the user's request; on the tracking fixtures Opus, Sonnet 5.5 and Haiku 5.5 all scored 22/22, at $0.16, $0.09 and about $0.007 for five runs).
  - Claude lookup: `claude-haiku-5-5` at effort `low`.
  - OpenAI overview and lookup: `gpt-6-luna` at reasoning effort `high` and `low`.
  Rationale: The cheapest model that passes the evaluation. Revisit when the evaluation grows. `gpt-6-luna` is confirmed.
  Date: 2026-11-16


## Outcomes & Retrospective

The agent (v0) runs end to end on both providers and can be benchmarked with `bun run eval`. The Swift side, bundling and signing are not started. The evaluation took 4 fixture stages; it should grow before model or prompt choices are made from it.


## Milestones

Work in `/Users/ethanchen/.supaterm/worktrees/martin/supaterm-54ab7fbe` (branch `supaterm/2e313e72`). Rebase onto `origin/main` before Milestone 4.

### Milestone 0: prototypes

Settle three unknowns in a scratch folder outside the repository, then throw it away. Record findings in `Surprises & Discoveries` and choices in the `Decision Log`.

1. **The binary runs signed.** Compile a tiny stdin-echo plus `fetch` program with `bun build --compile --target=bun-darwin-arm64`. Copy it into `build/Martin.app/Contents/MacOS/`, sign it with `--options runtime`, and run it. If it crashes under the hardened runtime, add `com.apple.security.cs.allow-jit`, and if needed `allow-unsigned-executable-memory`. Record the minimal set of entitlements and the binary size.
2. **Anthropic: tool loop ending in structured output.** Run `client.beta.messages.toolRunner` with one `betaZodTool` and `output_config: { effort: "high", format: zodOutputFormat(Result) }` on `claude-opus-5-5`. Confirm the model calls the tool and the final text parses. If not, use a strict `submit` tool as the final answer. Also confirm the request accepts the server-side fallback beta (`server-side-fallback-2026-07-01`, `fallbacks: "default"`).
3. **OpenAI: tool loop ending in JSON schema output.** Use `client.responses.create` with one function tool and `text.format` set to a strict `json_schema`. Loop on `function_call` items with `function_call_output` and `previous_response_id`. Take exact names from the installed SDK's types, and confirm the model id and the reasoning effort parameter.

### Milestone 1: agent package with a fake provider

Create `agent/` at the repository root. It holds:

- `package.json`: private and ESM, with exact-pinned `@anthropic-ai/sdk`, `openai` and `zod`, plus dev dependencies `typescript` and `@types/bun`. Scripts:
  - `check`: `tsc` then `bun test`;
  - `build`: compile `src/main.ts` to `dist/martin-agent`;
  - `eval`: run `eval/eval.ts` for explicit, live-provider evaluations and retrospectives.
- `tsconfig.json` (strict, `noEmit`) and `bun.lock`.
- `.gitignore` entries for `agent/node_modules/` and `agent/dist/`.

`src/schema.ts` defines the job, the events and the results with Zod. This is the contract with Swift; see Interfaces below.

`src/tools.ts` makes each tool from the job, so it can only see what the job names. Every tool returns text, and a failure returns an explanation instead of throwing. Read files and run commands without invoking a shell. Source read failures must remain distinguishable from empty sources; an unresolved file or activity read failure ends the job with an error rather than advancing the overview's `readAt`.

- **`read_note({ id, offset })`:**
  - refuses ids that aren't in the job;
  - defaults `offset` to zero and requires a nonnegative integer character offset;
  - reads the note's `path` once per job and keeps that text for subsequent pages;
  - returns at most 4,000 characters, the returned character range, and either the next offset or an explicit end-of-note marker;
  - reports when the same page has already been read, while allowing the next page to be read;
  - counts offsets and page lengths consistently by Unicode code point.
- **`repo_activity({ source, cursor })`:** offered only when the job has a repository. `source` is `commits` or `pullRequests`. The activity window runs from the previous `readAt`, or 30 days before the cutoff, to the cutoff. The model never supplies command arguments.
  - Commits come from a fixed `git -C <folder> log --all` argument array, with commit date, author name and email, and subject. A page holds at most 4,000 characters of whole records and ends with an opaque next cursor or an explicit end marker; `--skip` continues. Cursors are created by the tool and rejected when unknown. A newly fetched commit with an older commit date is a known limitation of this date-based query.
  - Pull requests come from one fixed `gh pr list --repo <slug> --state all --limit 30 --search "updated:>=<window start>" --json title,state,updatedAt,author` call, with title, state, updated time and author login. When 30 come back, the result says the cap was reached and older updates in the window are not shown. It reports current state only; it does not reconstruct an older state. `cursor` is not used for this source.
  - Each command runs without a shell and has a 30-second timeout. The provider's turn limit and the client's deadline still bound the whole job.

`src/jobs/overview.ts` returns a `JobSpec<OverviewResult>`.

- **System prompt.** It holds the rules and never changes between jobs, so providers can cache it:
  - three sections, most important first: now (at most 3 tasks), next (at most 6) and shelved (at most 6);
  - each task is a short title plus a one-sentence caption on where it stands;
  - `updated` is the date of the latest note or activity about the task, or null;
  - never mention pull request numbers, commit hashes or file names;
  - start from the previous overview, keep what still holds, and change only what the new material changes;
  - remove completed or cancelled tasks; move tasks between now, next and shelved when the evidence says their status changed;
  - treat shelved as explicitly paused or set-aside work, never as a conclusion drawn solely from silence;
  - use the note list and repository link to reassess previous claims; the previous overview is a draft, not independent evidence;
  - use repository activity to update project context and evidenced tasks, but do not assign another contributor's task to the user solely because it appears in the feed;
  - leave out anything the material doesn't support;
  - read only what is needed, follow continuation when the evidence needed to settle a task is beyond the current page, and read several notes at once when useful;
  - inspect repository activity when a repository is linked, including when no notes changed; never describe a failed source read as no activity.
- **Opening message:** the project name, today's date (derived from `cutoff` in its own timezone offset), the cutoff, the last-read date, the previous overview, and the note list: one line per note with its id, title, meeting date, edit date, and "new since last read" when it changed after the previous overview's `readAt`. Notes from before the last run remain readable, including older notes edited since that run.
- **`finish`:**
  - trims titles to 80 characters and captions to 160;
  - drops empty titles;
  - caps each section;
  - drops `updated` dates later than today.

`src/jobs/repositoryLookup.ts` returns a `JobSpec<LookupResult>`.

- **Prompt:** the project name, the five newest note excerpts and one line per clone (its slug plus a README summary).
- **Instructions:** quote the evidence, then list at most three slugs that the project's name or notes point to.
- **Tools:** none.
- **`finish`:** lowercases the slugs, and returns none when there are more than three.

`src/providers/provider.ts` defines the `Provider` interface. `src/providers/fake.ts` is a scripted provider for tests: it runs given tool calls for real, emits progress, and returns a given answer.

`src/main.ts`:
- reads stdin and parses it as a `Job`;
- chooses the job spec by `kind` and the provider by `provider`, taking the key from `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`;
- prints events as NDJSON;
- exits 0 after a result, or 1 after an error event;
- never logs the key or note contents.

Tests run with `bun test` and use a temporary folder and git repository:
- **Tools:** an unknown id or cursor is refused; note pages are bounded to 4,000 characters and can reach a completion update beyond the first page; Unicode offsets work; a repeated page is reported as already read; commit paging reaches records beyond the first page without gaps; the pull request listing says when its cap was reached; failed reads are distinguished from empty sources.
- **Opening message:** "new since last read" marks an edited older note, and today's date follows the cutoff's offset (a cutoff of `2026-11-17T20:00:00-08:00` gives `2026-11-17`, not `2026-11-18`).
- **`finish`:** both jobs.
- **Caching:** the system prompt is identical for two jobs with different dates.
- **End to end:** `main` with the fake provider prints progress lines and one result line and exits 0. A malformed job prints one error line and exits 1.

Acceptance: `cd agent && bun install && bun run check` passes, and `bun run build` produces `dist/martin-agent`.

### Milestone 2: Anthropic provider

`src/providers/anthropic.ts` implements `Provider` with `@anthropic-ai/sdk`:

- each `Tool` becomes a `betaZodTool` whose `run` emits a progress event;
- model and effort come from the job spec, with `max_tokens: 64000`, streaming on, and the system prompt marked `cache_control: { type: "ephemeral" }`;
- the server-side fallback is on for Opus;
- the loop is capped at 12 iterations;
- the final answer uses the mechanism chosen in Milestone 0;
- `refusal` and `max_tokens` stop reasons, and the SDK's typed errors, become short error events.

Add `agent/fixtures/sample/`: three short invented notes and a `job.json`. The live check:

    cd agent
    ANTHROPIC_API_KEY=... bun src/main.ts < fixtures/sample/job.json

Expect `read_note` progress lines, then one result line with now, next and shelved tasks taken from the sample notes. Add a stubbed-client test for the stop-reason and error mapping.

### Milestone 3: OpenAI provider

`src/providers/openai.ts` implements `Provider` with the `openai` Responses API, as proven in Milestone 0:

- function tools built from each tool's Zod schema with `z.toJSONSchema`;
- all of a response's `function_call` outputs sent back together;
- `text.format` set to the job's result schema with `strict: true`;
- reasoning effort from the job spec;
- the same 12-iteration cap and error mapping as the Anthropic provider.

Repeat the live check with `"provider": "openai"` and `OPENAI_API_KEY`, and add the same stubbed-client test.

### Milestone 4: bundle the agent and integrate Swift settings, keys and the client

**Bundle first.** `scripts/build-app.sh` runs `bun install --frozen-lockfile --cwd agent` and `bun run --cwd agent build`. It copies `dist/martin-agent` to the staged app's `Contents/MacOS/` and signs it with the hardened runtime and `app/Resources/MartinAgent.entitlements` before signing the app. Use the minimal entitlements proven in Milestone 0 and retain the script's final deep signature verification. This integration must exist before the built-app check below.

**MartinKit:**
- Add `Provider` (`anthropic`, `openai`) in its own file. It replaces `Assistant`.
- Add `APIKeys`: Keychain generic passwords under service `dev.ethanchen.martin`, with the provider as the account. It's injected as closures so tests use an in-memory store.
- Give `Command.run` an `environment:` parameter so the key reaches only the child process. Change its return value to preserve stdout and termination separately: normal exit with its status, termination by signal, or timeout. A spawn failure is a distinct error. Update existing callers to check successful termination explicitly rather than adding a second compatibility interface. Preserve the current process-tree cleanup and extend it to task cancellation.
- Add `AgentClient`:
  - mirrors the job and event types as `Codable`;
  - runs `Bundle.main.url(forAuxiliaryExecutable: "martin-agent")` with a 300-second deadline;
  - decodes stdout even after a nonzero exit, preserving an agent error event as a typed failure with a short user-facing message;
  - accepts exactly one terminal result matching the job kind only after exit 0; missing or duplicate terminal events, malformed NDJSON, a result followed by failure, and a mismatched result are protocol failures;
  - maps launch failure, timeout and signal termination without a valid terminal event to client failures, and propagates cancellation to the child process tree;
  - maps the wire task's `updated` date to Swift's `Overview.Task.updatedAt`; Swift sets `Overview.readAt` to the request's captured cutoff only when accepting a successful result.

**Repository lookup:**
- `Agent.match` now builds a lookup job and calls `AgentClient`.
- `Agent.pick` and `Agent.names` stay in Swift.
- The lookup prompt and the three-slug cap leave Swift.

**Deleted:** `Assistant.swift`, `Conductor.swift`, `AssistantSetup.swift` and their tests.

**Settings and state:**
- The Assistant section becomes a provider picker and an API key field with Save and Remove.
- `AppState.assistant` becomes `provider: Provider?`, stored in `UserDefaults` under `provider`. It's set only when a key is saved.
- Keep the existing repository lookup protection against obsolete results. Changing or removing the active key or provider invalidates and cancels work started with the previous credentials.

Tests: `Command.run` passes the environment through and preserves stdout from a child that exits 1. `AgentClient` decodes progress followed by one result and exit 0, and preserves an authentication error event followed by exit 1. Cover malformed and duplicate terminal events, mismatched result kinds, launch failure, timeout, and cancellation with child-process cleanup. Preserve the lookup tests for deletion and provider changes. Verify that the provider is remembered across launches and that the settings view renders off-screen.

Acceptance: `swift test --package-path app` passes with no warnings. `./scripts/build-app.sh` produces an app containing the signed `Contents/MacOS/martin-agent`, and deep signature verification passes. In that built app with a saved key, an unlinked project still gets its repository linked at launch.

### Milestone 5: the Overview on screen

**Storage.** `MeetingLibrary` gets `overviews()` and `save(_:for:)` backed by `overviews.json`, keyed by project id. Each `OverviewRecord` contains `overview: Overview?`, `basis: OverviewBasis?` and `checkedAt: Date`. `overview` is the last successful result. `basis` is the note ids and repository folder that result was built from; it is the only way to notice a removed note or a changed link later. `checkedAt` is when the project was last checked, whether the check was skipped, failed, manual or ran. Save `checkedAt` before starting a child process, preserving the previous overview. If that save fails, report the error and do not start the request. Deleting a project removes its record. Persisting the check time is necessary because skipped and failed checks have no new overview timestamp and relaunch must not reset the 30-minute gate.

**Schedule.** `AppState` owns one overview scheduler while the app is running. A project is eligible when it is active, non-secret, has notes, a linked repository or a previous overview, and a provider and its saved key are available. Including projects with a previous overview allows the next run to reassess their tasks after the last note is removed. A project is due when it has no record or at least 30 minutes have elapsed since `checkedAt`. A due project runs only when it has changed since its last successful overview:
- it has no successful overview;
- a note's edit date is after `readAt`;
- the project's note ids differ from `basis`;
- the linked repository folder differs from `basis`;
- `git -C <folder> log --all --since <readAt> -1` returns a commit, or `gh pr list --repo <slug> --state all --limit 1 --search "updated:>=<readAt>"` returns a pull request.

A git or gh failure counts as changed, so the agent's own error reporting takes over. An unchanged project only gets a new `checkedAt`. Add `Repository.hasActivity(since:) async -> Bool` for the two commands and remove `Repository.activity(since:)`, which the agent replaces.

Check for due work after the launch repository pass and when the app resumes, then wait until the next due time. Launch and resume only evaluate the same time gate; they do not force a refresh. Run due projects one at a time, and never overlap scheduler passes or replay missed intervals after sleep. Saving or editing notes, moving or deleting a note, linking a repository, and saving a key do not start an overview request. They are reflected at the next due check or manual command. If there are no eligible projects, including when no provider is configured, wait 30 minutes before checking again rather than spinning on overdue records. Saving a key leaves that scheduled check in place; the manual command remains available immediately. A manual refresh skips the change check and sets `checkedAt` too, so the next automatic check is 30 minutes later. Failed and discarded requests wait for the next check or a manual command rather than retrying immediately.

**State and request lifecycle.** `AppState` loads records from storage and exposes view state for each project as `.ready`, `.refreshing` or `.failed(message)`. Keep the stored overview in its record rather than duplicating its content in the view state; a missing record means the project has never been checked. Add `refreshDueOverviews()` for the scheduler and `refreshOverview(for:)` for the manual command. Both use the same eligibility and request handling; only the manual command bypasses the time gate and the change check.

Before starting a request, capture its cutoff time in the local timezone, the current project name, all current note ids, titles, dates, edit dates and paths, and the linked repository folder and slug. Build the job from that captured input and the previous overview. On success, save the captured note ids and repository folder as `basis`. There is at most one request per project; a manual command during that project's request joins the existing work and does not enqueue a second request. Keep an in-memory request identity and credential generation so an obsolete completion cannot overwrite state from a later request.

Before saving a result, confirm that the request is still the latest for its project, the project still exists and is eligible, and the active credentials are unchanged; otherwise discard it, retaining the previous overview and check time. Edits to notes or the repository link during the request do not discard it: `readAt` is the captured cutoff, never completion time, so those edits stay newer than `readAt` and `basis` and the next check runs the project again. Cancel and invalidate in-flight work on project deletion, archiving or becoming secret, and on active provider or key changes. No completion, cancellation or input edit starts a replacement request outside the scheduled or manual triggers.

On request failure, keep the previous overview and show the error. If there is no previous overview, show a short failure message and Refresh Overview instead of an empty success state or an endless spinner. A discarded request returns the surviving project's view state to ready without advancing its successful overview. Remove deleted projects from all in-memory request and overview state so a late completion cannot recreate their records. Inject the clock, scheduler wait and agent runner so these cases can be tested without waiting 30 minutes or making API calls.

**UI.** `ShelfView` in `app/Martin/NotesPage.swift` shows an `OverviewSection` next to the `RepositoryCard`:
- Now, Next and Shelved groups, each task with its title, caption and relative date;
- a quiet spinner while it refreshes;
- a short failure message with Refresh Overview, retaining the last successful tasks when available;
- nothing at all when no provider is set.

`ProjectActions` gets Refresh Overview. Disable it for ineligible projects and show that an existing request is already running rather than starting duplicate work.

**Tests**, with a stubbed `AgentClient`:
- no check happens at 29 minutes 59 seconds after `checkedAt`, and exactly one happens when 30 minutes have elapsed;
- a due project with nothing changed starts no request and only gets a new `checkedAt`;
- each change starts a request at the next check: an edited older note, an added note, a removed note (including the last one in a project with an overview), a changed repository link, a new commit, and a new pull request update; a failing activity query also starts one;
- a manual request runs before the deadline without the change check and moves the next check to 30 minutes after its start;
- an initial project is due without a prior record, and launch, resume, failure and relaunch all respect the persisted check time without replaying missed intervals;
- note saves, key saves and other input edits do not trigger requests by themselves;
- secret or archived projects and projects without credentials are never started, through either entry point;
- scheduler passes are serial, and scheduled and manual commands cannot start two requests for one project;
- a note edited during a request does not discard its result; `readAt` is the cutoff, and the next check runs the project again because of that edit;
- project deletion, archiving, becoming secret, and credential changes cancel or invalidate pending work; deliberately late completions cannot save an overview or recreate a deleted record;
- a failed run keeps the previous overview and check time; a first-run failure leaves an actionable error state and stops the spinner;
- the section renders tasks, refreshing state and first-run and subsequent failure states off-screen.

Acceptance: in the built app, a project with notes shows an Overview after Refresh Overview or its first due run. Editing a note does not start an agent; Refresh Overview picks up that edit immediately, and leaving it alone picks it up at the next 30-minute check. A project with nothing new starts no agent at its check. Automated clock-controlled tests prove the interval without a real-time wait. A bad key produces a visible failure message, and a successful refresh clears it.

### Milestone 6: checks, release and evaluation

**Checks.** `.githooks/pre-commit` runs the agent's `check`. `build.yml` and `release.yml` add `oven-sh/setup-bun`, pinned to an exact version. Confirm that notarization still passes.

**Tracking evaluation.** Add small, invented, immutable source snapshots under `agent/fixtures/tracking/`, with note files and recorded repository activity for each stage. The stages establish a task as next, start it, complete it, explicitly shelve another task, then leave an unrelated active task unchanged. Include a later note that overrides an earlier status, a completion update beyond character 4,000, and a teammate's separate repository task that must not become the user's work. Each stage declares expected task identities and section membership, including tasks that must be absent; allow short-title and caption wording to vary.

`agent/eval/eval.ts` accepts `--provider anthropic|openai` and either `--fixtures <folder>` or `--data <library folder> --snapshots <dates>`. With fixtures, it feeds the stages through the real provider using the fixture notes and recorded activity and checks their semantic expectations. Run both chained overviews and a final-stage overview from scratch; both must satisfy the final-stage expectations. Report failures by scenario and retain the inputs, tool calls and outputs for diagnosis. Fake-provider tests verify the fixture runner and assertions in `check`; they do not count as evidence of model quality. With `--data`, it runs chained overviews over a real library at each snapshot date, with no expectations, and is labelled a retrospective: it uses today's note contents and live GitHub state, not a historical replay. Every run writes the tool calls, seconds, tokens and overview. Live evaluation spends money and runs only when explicitly invoked, never in `check` or ordinary CI. Before accepting this milestone, run the fixtures on each provider and require all declared task-transition and attribution expectations to pass.

**README.** Update it: choosing Claude or OpenAI, pasting a key, where the key is kept, what is sent to the provider, the 30-minute check that refreshes only changed projects, the manual command, and how errors and retries behave.


## Concrete Steps

Run these from the repository root. Live sample and evaluation commands require the selected provider's key in the environment and are separate from ordinary checks.

    (cd agent && bun install && bun run check)
    (cd agent && bun run build && ls -lh dist/martin-agent)
    (cd agent && bun src/main.ts < fixtures/sample/job.json)
    swift test --package-path app
    ./scripts/build-app.sh && open -g -j build/Martin.app
    osascript -e "quit app \"$PWD/build/Martin.app\""
    (cd agent && bun run eval --provider anthropic --fixtures fixtures/tracking)
    (cd agent && bun run eval --provider openai --fixtures fixtures/tracking)

Expected live run (the shape, not the wording):

    {"type":"progress","tool":"read_note","input":{"id":"2026-11-02-091500"}}
    {"type":"result","result":{"now":[{"title":"Launch beta","caption":"Invites go out Friday.","updated":"2026-11-09"}],"next":[],"shelved":[]}}


## Validation and Acceptance

- **Agent:** `bun run check` passes. The end-to-end test gets progress lines, then exactly one result line and exit 0. A malformed job gets one error line and exit 1.
- **Evidence access:** a note completion update after the first 4,000 characters and commits beyond the first page can be retrieved, and a capped pull request listing says so. Unknown cursors are refused, and a source failure is not treated as an empty source or a successful refresh.
- **Providers:** the live check returns a valid overview from each provider, built from the sample notes through real tool calls.
- **Tracking quality:** both providers pass the declared fixture expectations for next-to-active, active-to-completed, explicitly shelved, contradictory and unchanged work, and attribution of teammate activity. Chained and from-scratch final runs both satisfy the final-stage expectations; valid JSON alone is insufficient.
- **App:**
  - `swift test --package-path app` passes with no warnings, and each new test fails without its change;
  - with a key saved, repositories link at launch using the bundled, signed agent, and eligible project overviews refresh when due and changed, or manually;
  - clock-controlled tests prove the 30-minute check across manual, skipped and failed checks and relaunch; note edits do not trigger agent runs by themselves;
  - a due project with no note edits, no membership or link change and no new commits or pull request updates starts no agent; any one of those changes starts one;
  - results from requests with mid-run edits are saved, and the next check runs again; superseded requests, project deletion and credential changes cannot overwrite state, advance `readAt`, or recreate deleted records;
  - error events survive nonzero process exits; first-run failures stop the spinner and show an actionable message, while later failures retain the previous overview;
  - with no key, no agent ever starts and no Overview section appears.


## Idempotence and Recovery

Milestones 0 to 3 only add code. Do Milestone 4's deletions in their own commit so they can be reverted alone. Live sample runs and evaluations cost money but change nothing on disk except their output files. Keep test notes in `agent/fixtures/` or a temporary directory, never in `~/Library/Application Support/Martin/`. Never commit an API key. Failed or discarded app requests preserve the last successful overview and their persisted check time; recovery is the next check or the manual command.


## Artifacts and Notes

Filled in during Milestone 0: the binary size, the entitlements and one transcript per provider prototype.


## Interfaces and Dependencies

The agent depends on `@anthropic-ai/sdk`, `openai` and `zod`, pinned to exact versions, plus `bun` and `typescript` to build.

The contract in `agent/src/schema.ts`, mirrored in Swift's `AgentClient`. `cutoff`, `changedAt`, `readAt` and `checkedAt` are ISO 8601 timestamps with a timezone offset; Swift writes `cutoff` in the user's local timezone. Task `updated` values are valid YYYY-MM-DD dates or null. Derive today's date from `cutoff` in the offset it carries rather than sending another field for it. Note `date` is the meeting timestamp. Swift converts between wire task dates and `Overview.Task.updatedAt` explicitly.

    Job =
      | { kind: "overview", provider: "anthropic" | "openai",
          project: { name: string }, cutoff: string,
          previous: Overview | null,
          notes: { id: string, title: string, date: string, changedAt: string, path: string }[],
          repository: { folder: string, slug: string } | null }
      | { kind: "repositoryLookup", provider: "anthropic" | "openai",
          project: { name: string },
          notes: { title: string, path: string }[],
          candidates: { slug: string, summary: string | null }[] }

    Overview = { now: Task[], next: Task[], shelved: Task[], readAt: string }
    Task     = { title: string, caption: string, updated: string | null }

    Event =
      | { type: "progress", tool: string, input: unknown }
      | { type: "result", result: OverviewResult | LookupResult }
      | { type: "error", message: string }

    OverviewResult = { now: Task[], next: Task[], shelved: Task[] }
    LookupResult   = { evidence: string, slugs: string[] }

Swift alone owns the persisted record below; it sends only its `overview` as the next job's `previous`. `checkedAt` determines when the next automatic check is allowed, `readAt` records the input cutoff of a successful overview, and `basis` records which notes and repository that overview was built from. None is derived from another when checks are skipped, requests fail or results are discarded.

    OverviewRecord = { overview: Overview | null, basis: OverviewBasis | null, checkedAt: string }
    OverviewBasis  = { notes: string[], repository: string | null }

`agent/src/providers/provider.ts`:

    export type Tool = {
      name: string
      description: string
      input: z.ZodObject
      run: (input: unknown) => Promise<string>
    }

    export type JobSpec<Result> = {
      system: string
      prompt: string
      tools: Tool[]
      result: z.ZodType<Result>
      model: { anthropic: string, openai: string }
      effort: "low" | "high"
      finish: (result: Result) => Result
    }

    export interface Provider {
      run<Result>(spec: JobSpec<Result>, emit: (event: Event) => void): Promise<Result>
    }


## Revisions

- 2026-11-16: Removed the descriptions of the current code so the plan only says what to build next, as the user asked.
- 2026-11-17: Applied review feedback and the product decision to refresh only every 30 minutes or by manual command. Replaced note-change scheduling with a persisted attempt-time gate, defined obsolete-request and failure handling, preserved child error output, added paged evidence and task-transition evaluation, and moved bundling and signing into the Swift integration milestone so its acceptance check is executable.
- 2026-11-17: At the user's request, the 30-minute check now skips projects with nothing new since the last successful overview (stored `basis`, renamed `lastAttemptAt` to `checkedAt`); mid-run edits no longer discard results; today follows the cutoff's local offset; the `list_notes` tool is gone; pull requests use one capped `gh pr list`; the benchmark is merged into the evaluation script.
- 2026-11-17: Implemented Milestones 1–3 and the evaluation runner; recorded the strict-integer discovery and the live results.
- 2026-11-17: Claude overviews default to Haiku 5.5 instead of Opus 5.5, as the user asked.
