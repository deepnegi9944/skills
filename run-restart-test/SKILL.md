---
name: run-restart-test
description: Build and run the AIFM restart integration tests in the pensando/aicc-dev repo. Use when the user wants to run restart tests, run integ tests, build restart-test.bin, or execute test/integ/aifm/restart.
---

# Run Restart Integration Test

Three-step process: extract packages, build the test binary, then run it.

## Step 0: Extract debug packages

Run from `/home/deepnegi/src/github.com/pensando/aicc-dev/bin`:

```bash
tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/unified_controller_debug_package.tar -C /tmp && \
  tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/unified_agent_debug_package.tar -C /tmp
```

## Step 1: Build

```bash
cd /home/deepnegi/src/github.com/pensando/aicc-dev && \
  GOFLAGS=-mod=vendor \
  GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore \
  CGO_LDFLAGS_ALLOW="-I/usr/local/share/libtool" \
  go test -c -v -o /tmp/restart-test.bin ./test/integ/aifm/restart/
```

## Step 2: Run (single iteration)

```bash
GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore \
  /tmp/restart-test.bin -test.v -test.timeout 200m -ginkgo.v
```

## Combined (extract + build + run in one command)

```bash
tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/unified_controller_debug_package.tar -C /tmp && \
  tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/unified_agent_debug_package.tar -C /tmp && \
  cd /home/deepnegi/src/github.com/pensando/aicc-dev && \
  GOFLAGS=-mod=vendor \
  GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore \
  CGO_LDFLAGS_ALLOW="-I/usr/local/share/libtool" \
  go test -c -v -o /tmp/restart-test.bin ./test/integ/aifm/restart/ && \
  GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore \
  /tmp/restart-test.bin -test.v -test.timeout 200m -ginkgo.v
```

## Run multiple iterations (consistency/flakiness check)

Use `/tmp/run_consistency_tests.sh` to run the test binary N times and collect per-iteration logs + a final pass/fail summary.

**Script location**: `/tmp/run_consistency_tests.sh`

**Usage**:
```bash
/tmp/run_consistency_tests.sh [ITERATIONS]
```

**Examples**:
```bash
/tmp/run_consistency_tests.sh        # 10 iterations (default)
/tmp/run_consistency_tests.sh 5      # 5 iterations
```

**For overnight/background runs** (survives terminal disconnect):
```bash
nohup /tmp/run_consistency_tests.sh 10 &> /tmp/consistency_runner.log &
# or inside tmux:
tmux new-session -d -s consistency '/tmp/run_consistency_tests.sh 10'
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

**Prerequisites**: The test binary must already be built at `/tmp/restart-test.bin` (Step 1) and debug packages extracted (Step 0).

**When to use**: When the user asks to run tests multiple times, check for flakiness, run consistency tests, run overnight, or says something like "run it 5 times".

## Notes

- The build step compiles the test binary to `/tmp/restart-test.bin`.
- Timeout is set to 200 minutes to accommodate long-running restart scenarios.
- To run a specific test by name, append `-ginkgo.focus "<test name>"` to Step 2.
- If the binary already exists and the source hasn't changed, you can skip Step 1 and run Step 2 directly.
- Always send the command to the user's tmux session so output is visible in their terminal.
- **Ask the user which tmux session/window to use** before running. Do not assume a session name.
- Use `tmux list-sessions` and `tmux list-windows` to show available sessions if needed.
- Once the user specifies a target (e.g. `test`, `test:1`, `mysession:0.1`), send with:

```bash
tmux send-keys -t <session> "tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/unified_controller_debug_package.tar -C /tmp && tar -xvf /home/deepnegi/src/github.com/pensando/aicc-dev/bin/unified_agent_debug_package.tar -C /tmp && cd /home/deepnegi/src/github.com/pensando/aicc-dev && GOFLAGS=-mod=vendor GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore CGO_LDFLAGS_ALLOW=\"-I/usr/local/share/libtool\" go test -c -v -o /tmp/restart-test.bin ./test/integ/aifm/restart/ && GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore /tmp/restart-test.bin -test.v -test.timeout 200m -ginkgo.v" Enter
```

For multi-iteration runs via tmux:

```bash
tmux send-keys -t <session> "/tmp/run_consistency_tests.sh <N>" Enter
```
