---
name: run-registration-test
description: Build and run the AIFM registration integration test (test/integ/aifm/registration_test) inside the Docker build container. Use when the user wants to run registration tests, run the mockrack-tests CI target, debug registration test failures, or mentions registration_test.go.
---

# Run Registration Integration Test

The registration test runs inside the Docker build container via `make shell`. It exercises the full AIFM stack (apiserver, toposervice, config_mgr, mock rack) and validates compute node registration, GPU membership, and system VPod status.

## Prerequisites

- Docker must be running
- The build container image `registry.test.pensando.io:5000/aicc-bld:v1.8` must be available
- A tmux session must be available for interactive use

## Step 0: Find or create a tmux window

```bash
tmux list-sessions
tmux list-windows -a
```

Ask the user which tmux session/window to use. To create a new window in session `test`:

```bash
tmux new-window -t test -n regtest
```

## Step 1: Enter the Docker build shell

Send to tmux (replace `<target>` with session:window, e.g. `test:regtest`):

```bash
tmux send-keys -t <target> "cd /home/deepnegi/src/github.com/pensando/aicc-dev-main && make shell" Enter
```

Wait for the Docker shell prompt. You can poll with:

```bash
tmux capture-pane -t <target> -p | tail -5
```

Look for a bash prompt inside the container (working dir `/import/src/github.com/pensando/aicc-dev`).

## Step 2: Run the registration test (inside Docker)

Once inside the Docker shell, run:

```bash
tmux send-keys -t <target> "cd test/ci_targets/aifm && make" Enter
```

This executes the CI Makefile target `mockrack-tests`, which runs:

```
GOFLAGS=-mod=vendor VENICE_DEV=1 GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore \
  CGO_LDFLAGS_ALLOW="-I/usr/local/share/libtool" \
  go test -v github.com/pensando/aicc-dev/test/integ/aifm/registration_test
```

### Focus a single spec

To run only one `It` block, append ginkgo flags:

```bash
tmux send-keys -t <target> "GOFLAGS=-mod=vendor VENICE_DEV=1 GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore CGO_LDFLAGS_ALLOW=\"-I/usr/local/share/libtool\" go test -v github.com/pensando/aicc-dev/test/integ/aifm/registration_test -ginkgo.focus='Create pod and compute node and check status' -ginkgo.v" Enter
```

### Run N iterations for flakiness check

```bash
tmux send-keys -t <target> "PASS=0; FAIL=0; for i in \$(seq 1 20); do echo \"=== Iteration \$i ===\"; GOFLAGS=-mod=vendor VENICE_DEV=1 GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore CGO_LDFLAGS_ALLOW=\"-I/usr/local/share/libtool\" go test -v -count=1 github.com/pensando/aicc-dev/test/integ/aifm/registration_test -ginkgo.focus='Create pod and compute node and check status' -ginkgo.v && PASS=\$((PASS+1)) || FAIL=\$((FAIL+1)); done; echo \"PASS=\$PASS FAIL=\$FAIL\"" Enter
```

## Step 3: Monitor output

Poll the tmux pane for test progress:

```bash
tmux capture-pane -t <target> -p | tail -20
```

Look for Ginkgo summary lines:

- `Ran N of M Specs` — how many specs executed
- `SUCCESS!` or `FAIL!` — overall result
- `Timed out after` — timeout failures (common flake signature)

## Step 4: Exit Docker shell

```bash
tmux send-keys -t <target> "exit" Enter
```

## Key files

| File | Purpose |
|------|---------|
| `test/ci_targets/aifm/Makefile` | CI target: `mockrack-tests` (registration) and `restart-test` |
| `test/integ/aifm/registration_test/registration_test.go` | Test specs |
| `test/integ/aifm/registration_test/main_test.go` | Suite setup: apiserver, toposervice, config_mgr, mock rack |
| `test/integ/aifm/registration_test/utils_test.go` | Test helper utilities |
| `test/integ/aifm/registration_test/topo.json` | Topology file for mock rack |

## Notes

- The test takes ~2-3 minutes per run (90s Eventually polls + setup/teardown).
- Always send commands to tmux — the Docker shell is interactive and cannot be driven by the Shell tool directly.
- The Docker container mounts the repo at `/import/src/github.com/pensando/aicc-dev` — edits in the host workspace are visible inside the container immediately.
- `VENICE_DEV=1` is required; it switches to in-memory KV store and disables TLS.
