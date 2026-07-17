# SunshineBSD Engineering Rules

These rules apply to SunshineBSD's own code (`src/`, `tools/`, `tests/`).
They do not apply to the vendored FreeBSD tree.

## 1. One File, One Responsibility

- A source file does exactly one job. If a file needs the word "and" to
  describe it, split it.
- Pure logic and I/O live in separate files. Generators compute content;
  only `fs.lua` touches the filesystem; only `build.lua` decides what gets
  written where.
- Orchestration (wiring modules together) is itself one job and gets its
  own file.

## 2. One Test File, One Module

- `tests/test_X.lua` tests `X.lua` and nothing else.
- Every test file is standalone: `lua tests/test_X.lua` from the repo root
  runs just that suite and exits non-zero on failure.
- The Makefile runs each suite in its own interpreter process. Suites must
  not depend on each other or on execution order.
- Cross-module behaviour is tested only in the orchestrator's suite
  (`test_build.lua`, `test_cli.lua`).

## 3. NASA-Style Defensive Code

Adapted from the JPL "Power of Ten" rules to Lua:

1. Every public function validates the type and range of every argument
   and fails with a message naming the function and the violation.
2. Every return value of an I/O operation is checked. No call to
   `io.open`, `os.execute`, `write`, or `close` goes unexamined.
3. Loops are bounded. Anything that iterates over external input has an
   explicit upper limit (file size, file count, key count, path length).
4. No silent failure and no silent fallback. Errors propagate as
   `nil, error` pairs or as raised errors — never as ignored state.
5. Validation collects **all** errors before reporting, so one run of
   `sunconfig check` shows every problem in the configuration.
6. Writes are verified: after writing a file, read it back and compare.
7. Destructive helpers (e.g. `remove_tree`) refuse dangerous arguments
   (roots, short paths) even when callers "know what they're doing".
8. Untrusted input (user configuration) is evaluated only inside a
   sandbox with no `io`, no `os`, no `require`, and no bytecode loading.

## 4. Testing Standards

- Test the contract, not the implementation: valid input, invalid input,
  boundary values, and failure paths for every public function.
- Generators are pure functions; their suites assert exact (golden)
  output, byte for byte.
- Every validation rule has at least one test that proves it rejects bad
  input. A rule without a rejection test does not exist.
- Test count is expected to exceed function count several times over.

## 5. Makefile Discipline

- Every workflow (test, single suite, check) is a Makefile target.
- `make test` must pass on FreeBSD and on a development host with only
  `lua` and `make` installed. Nothing may depend on developer-specific
  paths.
