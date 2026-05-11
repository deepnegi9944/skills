---
name: run-restart-test
description: Build and run the AIFM restart integration tests in the pensando/aicc-dev repo. Use when the user wants to run restart tests, run integ tests, build restart-test.bin, or execute test/integ/aifm/restart.
---

# Run Restart Integration Test

Four-step process. Steps 3 and 4 are **mandatory** and always run. Steps 1 and 2 are **optional** — always ask the user before running them. All commands MUST be sent to a tmux session so the user can see the output live.

## Required up-front questions (ALWAYS ask before doing anything)

Before running anything, you MUST ask the user:

1. **Which tmux session/window/pane to use?** (e.g. `test`, `test:0`, `mysession:1.0`)
   - Use `tmux list-sessions` and `tmux list-windows -t <session>` to show options if helpful.
   - Never assume a session name — ask every time.
2. **Run Step 1 (`make build-debug-all`)?** — yes/no.
3. **Run Step 2 (extract debug tar packages to `/tmp`)?** — yes/no.

Steps 3 (build the test binary) and 4 (run the test binary) are always executed — do not ask about these.

## Step 1 (optional, ask): Build all debug binaries

```bash
cd /home/deepnegi/src/github.com/pensando/aicc-dev && make build-debug-all
```

## Step 2 (optional, ask): Extract debug packages

```bash
tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/afm_controller_debug_package.tar -C /tmp && \
  tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/afm_agent_debug_package.tar -C /tmp
```

## Step 3 (mandatory): Build the restart test binary

```bash
cd /home/deepnegi/src/github.com/pensando/aicc-dev && \
  GOFLAGS=-mod=vendor \
  GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore \
  CGO_LDFLAGS_ALLOW="-I/usr/local/share/libtool" \
  go test -c -v -o /tmp/restart-test.bin ./test/integ/aifm/restart/
```

## Step 4 (mandatory): Run the restart test binary

```bash
GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore \
  /tmp/restart-test.bin -test.v -test.timeout 200m -ginkgo.v -ginkgo.timeout=200m
```

## Sending the chosen steps to tmux

Always dispatch via `tmux send-keys` to the user-specified target. Chain only the steps the user opted into, plus the mandatory steps 3 and 4, with `&&` so a failure stops the chain.

Examples (replace `<session>` with the target the user gave you):

**All four steps (user said yes to 1 and 2):**
```bash
tmux send-keys -t <session> "cd /home/deepnegi/src/github.com/pensando/aicc-dev && make build-debug-all && tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/afm_controller_debug_package.tar -C /tmp && tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/afm_agent_debug_package.tar -C /tmp && cd /home/deepnegi/src/github.com/pensando/aicc-dev && GOFLAGS=-mod=vendor GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore CGO_LDFLAGS_ALLOW=\"-I/usr/local/share/libtool\" go test -c -v -o /tmp/restart-test.bin ./test/integ/aifm/restart/ && GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore /tmp/restart-test.bin -test.v -test.timeout 200m -ginkgo.v -ginkgo.timeout=200m" Enter
```

**Skip Step 1, do Step 2 + 3 + 4:**
```bash
tmux send-keys -t <session> "tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/afm_controller_debug_package.tar -C /tmp && tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/afm_agent_debug_package.tar -C /tmp && cd /home/deepnegi/src/github.com/pensando/aicc-dev && GOFLAGS=-mod=vendor GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore CGO_LDFLAGS_ALLOW=\"-I/usr/local/share/libtool\" go test -c -v -o /tmp/restart-test.bin ./test/integ/aifm/restart/ && GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore /tmp/restart-test.bin -test.v -test.timeout 200m -ginkgo.v -ginkgo.timeout=200m" Enter
```

**Skip Steps 1 and 2, only mandatory 3 + 4:**
```bash
tmux send-keys -t <session> "cd /home/deepnegi/src/github.com/pensando/aicc-dev && GOFLAGS=-mod=vendor GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore CGO_LDFLAGS_ALLOW=\"-I/usr/local/share/libtool\" go test -c -v -o /tmp/restart-test.bin ./test/integ/aifm/restart/ && GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore /tmp/restart-test.bin -test.v -test.timeout 200m -ginkgo.v -ginkgo.timeout=200m" Enter
```

## Run multiple iterations (consistency/flakiness check)

Use `/tmp/run_consistency_tests.sh` to run the test binary N times and collect per-iteration logs + a final pass/fail summary.

**Usage**:
```bash
/tmp/run_consistency_tests.sh [ITERATIONS]
```

**Examples**:
```bash
/tmp/run_consistency_tests.sh        # 10 iterations (default)
/tmp/run_consistency_tests.sh 5      # 5 iterations
```

**Send via tmux** (always use the user-specified session):
```bash
tmux send-keys -t <session> "/tmp/run_consistency_tests.sh <N>" Enter
```

**What it does**:
1. Runs `/tmp/restart-test.bin` N times sequentially
2. Saves per-iteration logs to `/tmp/restart_consistency_runs/<timestamp>/iteration_<N>/`
3. Copies `/tmp/restart_test.log` and `/tmp/restart_test_logs/` per iteration
4. Extracts and prints the Ginkgo summary for each iteration
5. Prints a final summary: total iterations, passed, failed
6. Exits non-zero if any iteration failed

**Output structure**:
```
/tmp/restart_consistency_runs/<timestamp>/
├── summary.txt                         # overall pass/fail summary
├── iteration_1/
│   ├── restart_test.log                # detailed test log
│   └── restart_test_logs/              # per-test failure zips
├── iteration_2/
│   └── ...
└── ...
```

**Prerequisites**: The test binary must already be built at `/tmp/restart-test.bin` (Step 3) and debug packages extracted (Step 2).

**When to use**: When the user asks to run tests multiple times, check for flakiness, run consistency tests, run overnight, or says something like "run it 5 times".

## Notes

- **tmux is required** — never run these commands directly in the shell. Always send to the user's tmux session via `tmux send-keys`.
- **Always ask** which tmux session/window to use; never assume a session name.
- **Always ask** before running Step 1 (`make build-debug-all`) and Step 2 (extract tars). Steps 3 and 4 always run.
- The build step (Step 3) compiles the test binary to `/tmp/restart-test.bin`.
- Timeout is set to 200 minutes (`-test.timeout 200m -ginkgo.timeout=200m`) to accommodate long-running restart scenarios.
- To run a specific test by name, append `-ginkgo.focus "<test name>"` to Step 4.
- After dispatching, you can observe progress via `tmux capture-pane -t <session> -p` or by reading the corresponding terminal file.
