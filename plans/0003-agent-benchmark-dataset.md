# Repository-first overviews, and a benchmark that tells models and prompts apart

The overview benchmark (`bun run eval`) has one invented project, Lumen, in four stages. Claude Haiku, Sonnet and Opus 5.5 and OpenAI all score 22/22, so it can't guide a choice of model or prompt.

The agent also treats notes as the source of truth and the repository as background. That is backwards for code projects. This plan does two things:

- makes the repository the source of truth for code work, with notes supplying intent;
- replaces the dataset with four projects graded by a pinned judge, including Martin's real GitHub activity.


## What's wrong today

**The dataset**

- Extra tasks cost nothing. Haiku put "Mobile role hiring" and "Next quarter planning proposal", both taken from the retro's chatter, into Next and still scored 22/22.
- Title regexes are brittle both ways. `album|shar` also matches anything about the share sheet. The checker takes the first section with a match, so duplicates and collisions go unseen, and a correct task under an unexpected name fails.
- Captions, `updated` dates, the order of Now and the section limits are never checked.
- Ownership is trivial. Commits are by `Me <me@example.com>`, and the agent is never told who the owner is.
- Repository activity never decides a status, because every status change is also written in a note. Commit paging and the PR cap are never reached.
- The previous overview is always correct, and no note is ever deleted.
- The notes don't look like real ones. Real notes are short checkbox lists, release checklists, idea lists, empty notes and non-meeting quick notes. Lumen is a long, tidy meeting retro.
- `--data` has no expectations, uses today's note contents, sets every note's edit date to its meeting date, has no repository, and sends real notes to the provider.

**The agent**

- The prompt says repository activity only "gives context", and that the agent must never shelve a task because nothing was said about it.
- `repo_activity` returns one flat commit list with no branch names. The agent can't tell work in progress from work that's done.
- It runs `git log --all`. In this clone that includes 402 local Supaterm checkpoint commits (`refs/supaterm/...`), which were never pushed and aren't work.
- It doesn't know who the owner is.

**What Martin's repository looks like**

- All 53 PRs are merged. The median time from opening to merging is under an hour, the longest is 2 hours, and there are no drafts and no issues.
- A PR is therefore a "done" event, not a task. Work in progress lives in unmerged branches, mostly local ones in worktrees.
- `ethanc/textkit2-notes-editor` and `ethanc/pr-one-liners` are unmerged and untouched since Oct 21.


## Decisions

**How overviews are built**

- **The repository is the source of truth for code work.** It decides started and done.
- **Notes supply intent.** They decide Next, explicit shelving and cancelling, and tasks that aren't code.
- **A ticked box (`- [x]`) means done**, even when the repository shows nothing.
- **A task is a theme that spans branches and PRs, or one large PR on its own.**
  - A theme: for example "martin-agent" covering #51, the self-hosted CI PRs and the benchmark branch.
  - A large PR: one big enough to be a piece of work by itself. In Martin the median PR changes 67 lines, the top tenth change 850 or more, and #8, #51, #39, #33, #7 and #40 change 850–2,400 lines each. A large PR can stand alone or anchor a theme; small PRs are grouped and never listed on their own.
  - The agent judges size from the lines added and removed, the files changed and the commit count. It isn't given a fixed threshold, and the rubric only uses clear-cut cases.
  - A task is in Now while its branches or PRs keep moving.
  - It's done when its work has merged and nothing has moved since, or when a note says it's done.
- **A stale branch means shelved.** When an unmerged branch has been idle for 2 days before the cutoff, its task moves to Shelved. This replaces the rule that nothing is shelved without being told.
  - Weekend days count as half a day. Days are calendar days in the cutoff's local time zone, measured from the branch's last commit.
  - Examples: a branch last touched Friday at 18:00 becomes stale on Monday at 18:00 (0.25 + 0.5 + 0.5 + 0.75). One touched Tuesday at 18:00 becomes stale on Thursday at 18:00.
  - Code works out each branch's idle time and whether it's stale, and the branches view reports both. The model only decides which task a branch belongs to.
- **Next comes from notes.** The repository has no issues or drafts to say what's next.
- **Owner identity.** The job carries the owner's git name, git email and GitHub login. A commit is the owner's when its name or email matches, and a PR is the owner's when its login matches.
- **Idea lists and checklists.** An idea list ("low hanging fruit: 1. … 2. …") is not a task until something says the owner is doing it. A release checklist is a single task, with the open items summarised in its caption.

**How the agent reads the repository**

- `repo_activity` gains a `branches` source. For each branch it lists the last commit date, idle days (weekends count half), whether it's stale, the number of commits ahead of main, whether it's merged, and the PR that belongs to it.
- Commits carry the branch they're on.
- Pull requests carry their size: lines added and removed, files changed and commit count.
- The commit source reads local branches, remote branches and tags instead of `--all`, so local work in progress stays visible and checkpoint refs disappear.

**The benchmark**

- **Data.** Martin uses its real GitHub activity, its real local branches and its 2 real notes, with no notes added. The other projects are invented, in the style of the real notes. `--data` is removed.
- **Size.** 4 projects with 1 repeat each.
- **Grading.** Claude Sonnet 5.5, pinned, judges each run against a rubric and returns pass or fail for every item, with a one-line reason. Verdicts are cached by a hash of the rubric, the overview and the judge model, so re-scoring a run is free. Invariants that code can check stay in code: the section limits, valid dates, and no PR numbers, commit hashes or file names.
- **Extras.** Each stage lists the extras it tolerates. Any other extra fails the stage's precision item. Tolerated extras count neither for nor against.


## Projects

1. **Martin**, the centrepiece.
   - Real data: commits with their branches, local and remote branches, and PRs from `ethanyxchen/martin`, Oct 19 – Nov 17, plus the 2 real notes, "Improvement Checklist" (with ticked boxes) and "Project Crunching".
   - Stages are weekly cutoffs, about Oct 26, Nov 2, Nov 9 and Nov 17. The first stage has repository activity only.
   - Expected themes are reconstructed from the branch and PR history.
   - Tests:
     - grouping small PRs into themes, while large PRs like "Link projects to their GitHub repository" (#39) and "Show images inline in notes" (#40) stand as tasks of their own;
     - fast-merged PRs meaning done;
     - stale branches becoming Shelved (`textkit2-notes-editor`, `pr-one-liners`);
     - the owner under three emails;
     - volume, about 70 commits on main and 53 PRs.
2. **A work app project, invented and Goodmeet-like**, mostly driven by the repository.
   - Repository:
     - teammates with real-looking names and emails, whose branches and PRs must stay out;
     - the owner reviewing a teammate's PR, which isn't a task;
     - a large PR that stays open and grows over three stages next to fast-merged small ones, so a large PR is seen in progress (Martin's history can't show this; see Open);
     - a stale branch that later gets picked up again (Shelved, then back to Now);
     - a branch left on a Friday and checked on Monday morning (still Now) and on Tuesday (Shelved);
     - more than 100 commits in one window, so paging is reached.
   - Notes:
     - "My tasks" checkbox lists ticked in later edits;
     - a release-testing checklist;
     - an idea list that later becomes a commitment;
     - an empty note titled "None";
     - a note that disagrees with the repository (it says the owner is on X, but X merged a week ago).
3. **Lumen, reworked** so the repository drives the status changes.
   - Started and done come from branches and merges. Next, the explicit shelve and the cancellation edit still come from notes.
   - Keeps the long retro with an update past character 4,000.
   - Authors get real names instead of "Me".
4. **A personal project with no repository, Interviews-like**, to test the notes-only fallback.
   - A first-person interview note that describes the owner and must produce no tasks.
   - A tentative "maybe apply to X" that stays out of Now.
   - A prep task with a relative date ("next Tuesday") that must resolve against the note's date.
   - More than 3 things active at once, to test the Now limit and its ordering.

A stage is one run, so the dataset is about 18–22 runs in total.


## Fixture format

Each project has a folder in `agent/fixtures/<project>/` containing `scenario.json` and `notes/`:

- `owner`: the owner's name, emails and GitHub login.
- `repository`: the repository, or null.
- `commits`: date, author name, author email, subject and branch.
- `pullRequests`: title, author login, branch, `createdAt`, `mergedAt`, `closedAt`, lines added and removed, files changed and commit count.
- At each cutoff, the following are derived from these, not stored:
  - which commits and PRs are visible;
  - each PR's state;
  - each branch's last commit, how far it's ahead of main, and whether it's merged.
- `stages`: each with a cutoff, its notes (file, title, date, `changedAt`), and a rubric:
  - `tasks`: a theme id, the expected section (or `absent`), what the caption must say, and the expected `updated` date. A date can be marked as anything reasonable.
  - `tolerated`: extras that are acceptable, described in words.
  - `order`: the expected order of Now, when it matters.

`eval/record.ts <folder> <owner/repo> <since> <until>` writes the `commits` and `pullRequests` for a real repository, including local branches. It's run once, and its output is committed. Invented projects write these by hand.


## Judge

- One request per run: the stage's rubric, the overview and the stage's source material.
- The judge returns `{ item, pass, reason }` for every rubric item, plus one precision item listing extras that aren't tolerated and any duplicates.
- Its price is reported separately from the agent's.
- It is pinned to `claude-sonnet-5-5` and has its own entry in `prices.ts`. Changing the judge invalidates past scores, so the judge model is recorded in every summary.


## Report

- Agent: pass counts per project and per kind of rubric item (section, caption, date, order, precision), plus seconds, tokens, agent cost, judge cost and tool calls per run.
- Re-reads: how often a note that hasn't changed since the last read is read again.
- `--project` runs a single project. Projects run in parallel, and stages within a project run in order.
- Expected cost of one pass: about $0.03 for Haiku as the agent, plus about $0.30 for the judge. A pass takes about 1 minute.


## Order of work

1. PR: the commit source reads branches, remotes and tags instead of `--all`, with a regression test using a checkpoint-style ref.
2. PR: the eval infrastructure.
   - The new fixture format with derived branch and PR state, `record.ts`, the judge and the report.
   - Removal of `--data`.
   - Lumen ported to the new format with its current expectations, so the switch to the new infrastructure can be checked on its own.
3. PR: the Martin, work-app and Interviews projects, and Lumen's repository-first rework.
   - Expectations follow the decisions above, so today's agent is expected to fail them.
   - Live baseline on Haiku in the description.
4. PR: the repository-first agent.
   - Owner identity on the job.
   - The `branches` source and branch on each commit.
   - A prompt rewritten for themes, repository-first status, stale branches meaning shelved, and notes for intent.
   - Before and after scores on Haiku, Sonnet and Opus in the description.


## Open

- **Martin's history hides how long large work took.** Branches are rebased or squashed on the day they merge: all of #51's commits are dated Nov 17, and all of #39's are dated Oct 29. A weekly replay only sees large PRs once they've merged, so large work in progress is tested only in the invented work-app project.
- **Martin's expected themes** come from the branch and PR history. They need your review, since only you know what you considered "now" each week.
- **OpenAI runs:** `gpt-6-luna` has no price, so they're refused until one is added.


## Later (product, not in this plan)

- **Suggest Next from the code.** Use the user's local coding agent (Claude Code or Codex) to read the code and propose next steps. Notes are the only source for Next until then.


## Appendix: Martin data that only exists on the work Mac

GitHub has the merged PRs and the pushed branches. These items exist only on the work Mac, so `record.ts` can't fetch them anywhere else; add them to the Martin fixture by hand. All times are as recorded.

Local branches that were never pushed, both unmerged and both stale at every cutoff after Oct 23:

    ethanc/pr-one-liners (4 commits ahead of main)
      2026-10-21T09:33:22+01:00  Ethan Chen <ethan.c@goodnotes.com>  Sum up each pull request in one line on the meeting page
      2026-10-21T09:59:12+01:00  Ethan Chen <ethan.c@goodnotes.com>  Lead the meeting page with two or three talking points over a timeline of your work
      2026-10-21T10:18:00+01:00  Ethan Chen <ethan.c@goodnotes.com>  Show only the talking points on the Work page
      2026-10-21T10:38:56+01:00  Ethan Chen <ethan.c@goodnotes.com>  Keep the talking points inside the page's text column
    ethanc/textkit2-notes-editor (1 commit ahead of main)
      2026-10-21T16:55:08+01:00  Ethan Chen <ethan.c@goodnotes.com>  Rebuild the notes editor on TextKit 2

The pushed but unmerged branch `origin/supaterm/2e313e72` has 1 commit: `2026-10-29T18:16:13Z  Ethan C <ethan.c@goodnotes.com>  Add a conductor agent that builds a project overview from its notes and GitHub activity`.

The owner's identities:

- Name: Ethan Chen, or Ethan C.
- Emails: ethan.c@goodnotes.com, ethanyxchen456@gmail.com (GitHub merge commits), ethanyxchen@berkeley.edu.
- GitHub login: ethanyxchen.

The 2 real notes from the Martin.app project in the Martin library. Neither is a meeting.

`improvement-checklist.md`, "Improvement Checklist", dated 2026-10-28T17:43:04Z:

    - [x] Add a new meeting note feature (does not have to be linked to meetings)
    - [x] Instead of sorting by meetings, sort by project

`project-crunching.md`, "Project Crunching", dated 2026-10-29T17:01:05Z:

    Three key sections under each project - NOT EDITABLE
    1. what you're working on right now
    2. next up
    3. shelved.

    Each Task should be expandable, containing "latest notes" and "latest work"

    Agent collecting context and building content

    Keep content simple and clean. Make the user feel organised, not overwhelmed.

    Small tasks/side-quests are kept together -> should show the user if they are getting off task
