# Launching the app

When launching Martin for testing, build it with `./scripts/build-app.sh` and always launch it in the background with `open -g -j build/Martin.app` so it never takes focus from other windows. Never run the executable inside the bundle directly, and never launch it through Xcode's Run; both bring the app to the foreground.

Quit Martin when you are done testing (`osascript -e 'quit app "Martin"'`), and close every window or panel you opened, including any test harness that puts panels on screen. Never leave seeded meetings in `~/Library/Application Support/Martin/`; seed test data in a temporary directory instead.

# Compiler warnings

The build must stay free of compiler warnings. The pre-commit hook in `.githooks/pre-commit` compiles with warnings treated as errors, type-checks the analyzer and runs its tests, and blocks the commit when anything fails; enable it once per clone with `git config core.hooksPath .githooks`. Whenever a build, `./scripts/build-app.sh`, or the hook reports a warning, fix its cause in the code right away, even when the warning is in code you did not touch. Never silence a warning, suppress a diagnostic, or bypass the hook with `--no-verify`.

# Tests

Run `swift test --package-path app` for the Swift side and `bun test` in `analyzer/` for the analyzer.

# Logs

Martin logs audio devices, transcription and assistant failures to the unified log under the subsystem `dev.ethanchen.martin`, in the categories `audio`, `transcription` and `assistant`. When Ethan reports a recording that went wrong, read them first (use the full path, since `log` is a shell builtin in zsh):

```sh
/usr/bin/log show --last 2h --style compact --predicate 'subsystem == "dev.ethanchen.martin"'
```
