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

## Step 2: Run

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
