# Launching the app

When launching Martin for testing, build it with `./scripts/build-app.sh` and always launch it in the background with `open -g -j build/Martin.app` so it never takes focus from other windows. Never run the executable inside the bundle directly, and never launch it through Xcode's Run; both bring the app to the foreground.

Quit Martin when you are done testing (`osascript -e "quit app \"$PWD/build/Martin.app\""`), and close every window or panel you opened, including any test harness that puts panels on screen. Never leave seeded meetings in `~/Library/Application Support/Martin/`; seed test data in a temporary directory instead.

In a linked git worktree, `./scripts/build-app.sh` builds a separate app, `Martin (<worktree>)`, with its own bundle identifier and a Dock icon tinted with a colour picked from the worktree name, so it runs beside the main checkout's Martin. Every build shares the released app's data, settings and API key, so a worktree build reads and writes your real meetings.

# Compiler warnings

The build must stay free of compiler warnings. The pre-commit hook in `.githooks/pre-commit` compiles with warnings treated as errors and blocks the commit when anything fails; enable it once per clone with `git config core.hooksPath .githooks`. Whenever a build, `./scripts/build-app.sh`, or the hook reports a warning, fix its cause in the code right away, even when the warning is in code you did not touch. Never silence a warning, suppress a diagnostic, or bypass the hook with `--no-verify`.

# Tests

Run `swift test --package-path app`.

Every bug fix and behaviour change comes with a regression test that fails without the change and passes with it; confirm both before committing. Logic in `MartinKit` is tested in `MartinKitTests`; app code in `app/Martin` (windows, views, the editor) is tested in `MartinTests` through `@testable import Martin`. Build any windows a test needs without ordering them on screen. Fall back to checking by hand in the built app only when a behaviour cannot be reached from a test, and say so in the PR.

# Benchmarking the agent

Run `bun run eval` in `agent/` with `claude-haiku-5-5` or `claude-sonnet-5-5` only. Never benchmark on Opus unless the owner asks for it in that conversation: on the full benchmark it scored within a few checks of Haiku at about fifteen times the agent cost.
