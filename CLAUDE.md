# Launching the app

When launching Martin for testing, build it with `./scripts/build-app.sh` and always launch it in the background with `open -g -j build/Martin.app` so it never takes focus from other windows. Never run the executable inside the bundle directly, and never launch it through Xcode's Run; both bring the app to the foreground.

Quit Martin when you are done testing (`osascript -e 'quit app "Martin"'`), and close every window or panel you opened, including any test harness that puts panels on screen. Never leave seeded meetings in `~/Library/Application Support/Martin/`; seed test data in a temporary directory instead.

# Compiler warnings

The build must stay free of compiler warnings. The pre-commit hook in `.githooks/pre-commit` compiles with warnings treated as errors and blocks the commit when anything fails; enable it once per clone with `git config core.hooksPath .githooks`. Whenever a build, `./scripts/build-app.sh`, or the hook reports a warning, fix its cause in the code right away, even when the warning is in code you did not touch. Never silence a warning, suppress a diagnostic, or bypass the hook with `--no-verify`.

# Tests

Run `swift test --package-path app`.
