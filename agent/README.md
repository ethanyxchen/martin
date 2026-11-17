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

`bun run eval` replays overviews stage by stage, each run starting from the previous overview, and records every run's time, tokens, cost, tool calls and overview in `eval/out/`. It refuses to run a model missing from `eval/prices.ts`.

    bun --env-file=../.env eval/eval.ts --provider anthropic --fixtures fixtures/tracking --scratch
    bun --env-file=../.env eval/eval.ts --provider anthropic --data "$HOME/Library/Application Support/Martin" --project Goodmeet --snapshots 2026-10-29,2026-10-31

`--fixtures` checks each stage's expected task sections. `--data` replays a real library without expectations, using today's note contents and no repository activity, and sends those notes to the provider. `--scratch` adds a final run without a previous overview. `--model` and `--effort` override the job's defaults.
