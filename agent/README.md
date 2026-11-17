# martin-agent

The program Martin runs for every model call. It reads one job as JSON on stdin and prints newline-delimited JSON events: `progress` for each tool call, then one `result` or `error`. It exits 0 after a result and 1 after an error.

Jobs:

- `overview` reads a project's notes and its repository's recent activity and returns the tasks being worked on now, next and shelved.
- `repositoryLookup` names the GitHub repositories that hold a project's code.

The provider is Claude (`ANTHROPIC_API_KEY`) or OpenAI (`OPENAI_API_KEY`), chosen by the job.

## Develop

    bun install
    bun run check
    bun run build
    bun --env-file=../.env src/main.ts < fixtures/sample/job.json

## Benchmark

`bun run eval` replays every project in `fixtures/` stage by stage, each run starting from the previous overview. Projects run in parallel and stages in order. Every run's time, tokens, cost, tool calls, overview and verdicts are written to `eval/out/`. It refuses to run a model missing from `eval/prices.ts`.

    bun --env-file=../.env eval/eval.ts --provider anthropic --scratch
    bun --env-file=../.env eval/eval.ts --provider anthropic --project lumen --model claude-sonnet-5-5

`--project` runs one project, by folder or name. `--scratch` adds a final run without a previous overview. `--model` and `--effort` override the job's defaults.

### Fixtures

Four projects are graded. Martin is this repository's real activity from Oct 19 to Nov 17, with its two real notes. Tandem is an invented work app with teammates, a large pull request in progress and more than 100 commits in one window. Lumen is an invented app whose branches and merges drive started and done. Interviews is a job search with notes only.

Each project is a folder holding `scenario.json` and its notes. A scenario has the project's owner (name, emails and GitHub login), its repository or null, the commits (date, author, email, subject and branch), the pull requests (title, author, branch, `createdAt`, `mergedAt`, `closedAt`, lines added and removed, files changed and commit count) and the stages. Each stage has a cutoff, the notes visible then, and a rubric.

At each cutoff the fixture works out which commits and pull requests are visible, each pull request's state, and each branch's last commit, how far it is ahead of main and whether it has merged. None of these are stored.

A rubric lists the expected tasks, each with a theme id, its section (`now`, `next`, `shelved` or `absent`), optionally what its caption must say and its `updated` date (a day, or `any` for any reasonable date); the extras it tolerates, in words; and optionally the order of Now.

`eval/record.ts` writes a real repository's commits and pull requests into a scenario. It reads commits from the local clone's branches, remotes and tags, so unpushed branches are included and checkpoint refs are not, and pull requests from `gh`. Run it from the repository's checkout:

    bun eval/record.ts <fixture folder> <owner/repo> <since> <until>

### Grading

Claude Sonnet 5.5 (`claude-sonnet-5-5`, pinned in `eval/judge.ts`) judges each run in one request, from the rubric, the overview and the stage's notes and repository state. It returns pass or fail with a one-line reason for every task's section, caption and date, for the order of Now, and for precision, which fails on an extra the stage doesn't tolerate or on two tasks covering the same theme. Verdicts are cached in `eval/cache/` by a hash of the rubric, the overview and the judge model, so re-scoring a run is free. The judge needs `ANTHROPIC_API_KEY` whichever provider is benchmarked.

Code checks the section limits, that dates are valid days up to the cutoff, and that no task mentions a pull request number, commit hash or file name.

The report gives pass counts per project and per kind of item, and the time, tokens, agent cost, judge cost and tool calls.
