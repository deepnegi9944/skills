---
name: aifm-restart-test-suite
description: >-
  Build, run, debug, and extend the AIFM restart integration test suite
  (Ginkgo/Gomega). Use when the user asks to run restart tests, write new
  checkpoint test cases, debug restart test failures, understand the
  restart test architecture, add new verification helpers, or work with
  debug builds for the restart suite. Also use when the user mentions
  restart tests, checkpoint tests, Ginkgo tests, build-debug-all,
  restart_test.go, utils_test.go, or AIFM integration tests.
---

# AIFM Restart Integration Test Suite

## Table of Contents

- [Overview](#overview)
- [Terminology](#terminology)
- [Repository Layout](#repository-layout)
- [Architecture](#architecture)
  - [Component Structure](#component-structure)
  - [File Organization](#file-organization)
  - [Checkpoint System](#checkpoint-system)
- [Build and Run](#build-and-run)
  - [Phase 1 — Build Debug Packages](#phase-1--build-debug-packages)
  - [Phase 2 — Extract to /tmp](#phase-2--extract-to-tmp)
  - [Phase 3 — Run the Tests](#phase-3--run-the-tests)
  - [Phase 4 — Review Logs](#phase-4--review-logs)
- [Test Suite Internals](#test-suite-internals)
  - [Suite Lifecycle (BeforeSuite / AfterSuite)](#suite-lifecycle-beforesuite--aftersuite)
  - [Test Contexts](#test-contexts)
  - [CheckpointTestCase Pattern](#checkpointtestcase-pattern)
  - [Entry vs XEntry](#entry-vs-xentry)
  - [Shared Pre-Trigger Action Sets](#shared-pre-trigger-action-sets)
- [Key Source Files — Full Reference](#key-source-files--full-reference)
  - [restart_suite_test.go](#restart_suite_testgo)
  - [restart_test.go](#restart_testgo)
  - [utils_test.go](#utils_testgo)
- [API Objects and Naming Conventions](#api-objects-and-naming-conventions)
- [Checkpoint Definitions](#checkpoint-definitions)
- [Helper Functions Reference](#helper-functions-reference)
  - [Process Lifecycle](#process-lifecycle)
  - [Verification Functions](#verification-functions)
  - [API Mutation Functions](#api-mutation-functions)
  - [Checkpoint and Recovery](#checkpoint-and-recovery)
  - [Cleanup and Logging](#cleanup-and-logging)
- [Writing New Test Cases](#writing-new-test-cases)
  - [Adding a New Checkpoint Test Entry](#adding-a-new-checkpoint-test-entry)
  - [Adding a New Self-Contained Context](#adding-a-new-self-contained-context)
  - [Adding a New Verification Helper](#adding-a-new-verification-helper)
- [Debugging Failures](#debugging-failures)
- [Common Pitfalls](#common-pitfalls)
- [Quick Reference Commands](#quick-reference-commands)

---

## Overview

The AIFM Restart Test Suite validates the resilience and recovery capabilities of the AIFM (AI Fabric Manager) controller when subjected to crashes at various checkpoints during operations like node registration, decommission, and VPod lifecycle management.

The suite simulates a mini AMD Helios rack: **1 controller, 2 compute node agents, and 1 switch agent** — all running as lightweight OS processes (not containers). It uses the Ginkgo/Gomega BDD testing framework with `go test` as the runner.

The core idea: inject crash points (checkpoints) into the controller, trigger operations that hit those checkpoints, let the controller crash, restart it, and verify that the system recovers to a consistent state.

**Design principles:**
1. **Extreme Lightweight** — All components run as OS processes, not containers or VMs
2. **API-Centric Validation** — Verification is done exclusively through the APIServer gRPC client
3. **Isolated Test Scoping** — Each `It()` block is self-contained; starts its own components and cleans up after

---

## Terminology

| Term | Meaning |
|------|---------|
| UC | Unified Controller (`unified_controller_debug` in test context) |
| UA | Unified Agent (`unified_agent_debug` in test context) |
| AICC-DEV | The main repository: `~/src/github.com/pensando/aicc-dev` |
| VM_IP | IP of the dev VM — detected by the suite via `net.InterfaceAddrs()` |
| Checkpoint | A crash injection point compiled into debug builds (`aifm_debug` build tag) |
| BeforeSuite | Ginkgo hook that runs once before all specs: cleans, starts UC, bootstraps, writes config |
| AfterSuite | Ginkgo hook that runs once after all specs: stops all agents and UC |
| Entry | An active Ginkgo `DescribeTable` row that **will** execute |
| XEntry | A pending/disabled Ginkgo `DescribeTable` row that is **skipped** |

---

## Repository Layout

All paths are relative to `~/src/github.com/pensando/aicc-dev`:

```
test/integ/aifm/restart/
├── doc.go                      # Package declaration only
├── README.md                   # Human-readable docs for the suite
├── restart_suite_test.go       # Ginkgo suite bootstrap, BeforeSuite/AfterSuite
├── restart_test.go             # Test specifications (Describe/Context/It/DescribeTable)
└── utils_test.go               # All helper functions (process mgmt, verification, API ops)

venice/aifm/utils/checkpoint/
├── checkpoint.go               # No-op Checkpoint() for non-debug builds
├── checkpoint_debug.go         # Panic-based Checkpoint() for debug builds (aifm_debug tag)
└── utils.go                    # CheckPoint type definition, all checkpoint constants, HTTP handler

test/ci_targets/aifm/
├── Makefile                    # CI targets: `restart-test`, `mockrack-tests`
└── ...
```

---

## Architecture

### Component Structure

```
Controller (1x)
    ├── Process: unified_controller_debug
    ├── Started from: /tmp/controller_pkg/unified_controller.sh start
    ├── APIServer gRPC port: 9003 (globals.APIServerPort)
    ├── AIFM Core REST port: 60009 (for checkpoint configuration)
    └── Bootstrap via: /tmp/controller_pkg/bootstrap.py

Compute Node Agents (2x, default)
    ├── Process: unified_agent_debug -slot-id 0 -controllers <IP>
    ├── Process: unified_agent_debug -slot-id 1 -controllers <IP>
    ├── Health endpoints: http://localhost:13000/api/health (port = 13000 + slotID)
    ├── Flags: AIFM_DEBUG=1 MOCKRACK=1
    └── Started from: /tmp/agent_pkg/unified_agent_debug

Switch Agents (1x, default)
    ├── Process: unified_agent_debug -slot-id 0 -agent switch -controllers <IP>
    ├── Health endpoint: http://localhost:13018/api/health (port = 13000 + 18 + slotID)
    ├── Flags: AIFM_DEBUG=1 MOCKRACK=1
    └── Started from: /tmp/agent_pkg/unified_agent_debug
```

### File Organization

| File | Purpose |
|------|---------|
| `restart_suite_test.go` | Suite entry point. Defines `TestRestart(t)` which calls `RunSpecs`. `BeforeSuite` cleans env, starts UC, bootstraps cluster, writes AIFM config, creates API client. `AfterSuite` stops all. |
| `restart_test.go` | Test specs organized as `Describe > Context > It/DescribeTable`. Contains `CheckpointTestCase` struct and all table entries. |
| `utils_test.go` | ~1700 lines of helpers: process start/stop, health checks, API verification, GPU disassociation, decommission, VPod CRUD, checkpoint configuration, failure log collection. |

### Checkpoint System

Debug builds (`aifm_debug` build tag) include crash injection points. The checkpoint mechanism:

1. **Compile time**: `checkpoint_debug.go` provides `Checkpoint(point)` that panics if the flag is set; `checkpoint.go` provides a no-op version for production builds.
2. **Runtime configuration**: The test sets checkpoint flags via HTTP POST to `http://<controllerIP>:<AifmCoreRestPort>/debug/checkpoint` with `{"set": [<checkpoint_value>]}`.
3. **Trigger**: When the controller code path hits `checkpoint.Checkpoint(CheckpointXxx)`, it panics (crashes the process).
4. **Recovery**: The test restarts the controller and validates state consistency.

Checkpoint values are bitmask constants (powers of 2) defined in `venice/aifm/utils/checkpoint/utils.go`.

---

## Build and Run

### Phase 1 — Build Debug Packages

From repo root (`~/src/github.com/pensando/aicc-dev`):

```bash
make build-debug-all
```

This runs both `build-unified-controller-debug` and `build-unified-agent-debug` Makefile targets with the `aifm_debug` Go build tag and `AIFM_DEBUG=1`.

Artifacts produced:
- `bin/unified_controller_debug_package.tar`
- `bin/unified_agent_debug_package.tar`

Individual targets:
```bash
make build-unified-controller-debug   # UC only
make build-unified-agent-debug        # UA only
```

The build runs inside Docker and can take 10–20 minutes.

### Phase 2 — Extract to /tmp

```bash
tar -xvf ./bin/unified_controller_debug_package.tar -C /tmp
tar -xvf ./bin/unified_agent_debug_package.tar -C /tmp
```

This creates `/tmp/controller_pkg/` and `/tmp/agent_pkg/` containing:
- Debug binaries: `unified_controller_debug`, `unified_agent_debug`
- Wrapper scripts: `unified_controller.sh`, `unified_agent.sh`
- Bootstrap script: `bootstrap.py`

**Overlay updated wrapper scripts** (optional — only if you've edited scripts locally):
```bash
cp /tmp/unified_controller.sh /tmp/controller_pkg/
cp /tmp/unified_agent.sh /tmp/agent_pkg/
```

### Phase 3 — Run the Tests

**Prerequisites**: Debug packages extracted to `/tmp` (Phase 2).

**Config prerequisite**: Ensure `nic/agent/cmd/unified-agent/aifm-config.yml` has the dev VM IP before building. Alternatively, the test passes `-controllers <IP>` directly to agents.

```bash
export GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore
cd ~/src/github.com/pensando/aicc-dev/test/integ/aifm/restart
ginkgo -v
```

Or via CI Makefile:
```bash
cd ~/src/github.com/pensando/aicc-dev/test/ci_targets/aifm
make restart-test
```

The CI Makefile sets required env vars and passes `-timeout 60m`:
```makefile
restart-test:
	@GOFLAGS=-mod=vendor GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore \
	 CGO_LDFLAGS_ALLOW="-I/usr/local/share/libtool" \
	 go test -v -timeout 60m github.com/pensando/aicc-dev/test/integ/aifm/restart
```

**Running a single test by name**:
```bash
ginkgo -v --focus "should be successfully connected"
ginkgo -v --focus "force decommission"
ginkgo -v --focus "TopoService before AddToStore during SwitchNode decommission"
```

### Phase 4 — Review Logs

- **Test suite log**: `/tmp/restart_test.log` — contains all `logger.Infof/Warnf/Errorf` output
- **Failure log archives**: `/tmp/restart_test_logs/<sanitized_test_name>.zip` — component logs archived per failed test
- **Component logs**: `aifmglobals.LogsDir` (typically `/opt/amd/aifm/logs/`) — cleaned between specs

---

## Test Suite Internals

### Suite Lifecycle (BeforeSuite / AfterSuite)

**BeforeSuite** (runs once before all specs):
1. Creates a log file at `/tmp/restart_test.log`
2. Calls `cleanAll()` → stops any running processes, removes state directories
3. Starts the unified controller
4. Bootstraps the AIFM cluster (`bootstrap.py` with cluster name `testcluster`, pod name `pod-1`)
5. If bootstrap fails, retries with a full clean + restart
6. Writes AIFM config (`/opt/amd/aifm/configs/config.yml`)
7. Creates gRPC API server client (`apiServerClient`)

**AfterSuite** (runs once after all specs):
1. Stops all node agents
2. Stops all switch agents
3. Stops the controller
4. Closes the log file

**ReportAfterEach** (runs after each spec):
- On failure: archives component logs to `/tmp/restart_test_logs/<test_name>.zip`
- Always: cleans component log directory for isolation

### Test Contexts

The test file (`restart_test.go`) has four top-level contexts:

1. **"when system is brought up"** — Basic end-to-end health check
   - Starts all components, verifies pod exists, agents connect, nodes register, ScaleUpInfo populates

2. **"when controller is restarted"** — Simple restart recovery
   - Starts all, stops controller, restarts controller, verifies agents reconnect

3. **"when checkpoint failures are triggered"** — `DescribeTable` with `CheckpointTestCase` entries
   - Parameterized checkpoint crash + recovery tests (the bulk of the suite)
   - Each entry: configures a checkpoint → triggers an action → controller crashes → restart → verify recovery

4. **"when compute node decommission fails with agent down"** — Force decommission flow
   - Tests `DECOMMISSION_FAILED` sticky state and force decommission with/without agent

### CheckpointTestCase Pattern

The central testing pattern used by the `DescribeTable`:

```go
type CheckpointTestCase struct {
    checkpoint            aifmutils.CheckPoint       // Which checkpoint to set
    description           string                     // Human-readable test name
    preTriggerActions     []preTriggerAction          // Setup steps before crash
    triggerAction         func() error               // Action that triggers the crash
    additionalValidations []ValidationFunc            // Post-recovery validations
    cleanUpActions        []cleanUpAction             // Post-test cleanup
}
```

**Execution flow for each entry:**
1. Start unified controller
2. Wait for controller ready (TCP port check)
3. Execute `preTriggerActions` in order (with Eventually retries)
4. Configure the crash checkpoint via HTTP POST
5. Execute `triggerAction` (this causes the controller to crash)
6. Verify controller process has terminated
7. Restart controller
8. `verifyControllerRecovery()` → verifies pod still exists
9. Execute `additionalValidations` (with Eventually retries)
10. Execute `cleanUpActions`
11. `defer stopAll()` ensures cleanup even on failure

### Entry vs XEntry

- **`Entry(...)`** — Active test case that runs during `ginkgo -v`
- **`XEntry(...)`** — Pending/disabled test case, skipped during execution

Currently active entries (Entry):
- TopoService before/after AddToStore during SwitchNode decommission
- Config Manager before/after/within SwitchNode Decommission

Currently disabled entries (XEntry):
- TopoService before/after AddToStore (basic node registration)
- Config Manager before ComputeNode Decommission
- TopoService during ComputeNode decommission
- All VPod lifecycle entries (create/update/delete × TopoService/NodeMgr/SwitchMgr)

To enable a disabled entry, change `XEntry` to `Entry` in `restart_test.go`.

### Shared Pre-Trigger Action Sets

Two reusable action sequences for VPod-related tests:

**`vpodCreatePreTriggerActions`** (5 actions):
1. Start 2 unified node agents
2. Start 1 unified switch agent
3. Verify ScaleUpInfo is populated
4. Disassociate GPUs from system VPod for slot 0
5. Disassociate GPUs from system VPod for slot 1

**`vpodUpdateDeletePreTriggerActions`** (3 actions):
1. Start 2 unified node agents
2. Start 1 unified switch agent
3. Verify ScaleUpInfo is populated

---

## Key Source Files — Full Reference

### restart_suite_test.go

**Package**: `restart`

**Constants**:
- `podID = 1`
- `unifiedControllerProcessName = "unified_controller_debug"`
- `controllerScriptPath = "unified_controller.sh"`
- `bootstrapScriptPath = "bootstrap.py"`

**Global variables**:
- `logger log.Logger` — Suite-wide logger
- `controllerIP string` — Detected VM IP address
- `setupDone bool` — Prevents double-initialization
- `logFile *os.File` — Log file handle
- `unifiedControllerCmd *exec.Cmd` — Controller process handle
- `bootstrapCmd *exec.Cmd` — Bootstrap process handle
- `unifiedNodeAgentCmds []*exec.Cmd` — Slice of node agent process handles
- `unifiedSwitchAgentCmds []*exec.Cmd` — Slice of switch agent process handles
- `apiServerClient apiclient.Services` — gRPC client to APIServer

**Imports** (key packages):
- `github.com/onsi/ginkgo/v2` — BDD test framework
- `github.com/onsi/gomega` — Matcher library
- `github.com/pensando/aicc-dev/api/client` — gRPC upstream client factory
- `github.com/pensando/aicc-dev/api/generated/apiclient` — Generated API client interfaces
- `github.com/pensando/aicc-dev/venice/globals` — Port constants (`APIServerPort`)
- `github.com/pensando/aicc-dev/venice/utils/log` — Logger

### restart_test.go

**Imports** (key packages):
- `github.com/pensando/aicc-dev/api` — ObjectMeta, TypeMeta, ListWatchOptions
- `github.com/pensando/aicc-dev/api/generated/cluster` — Cluster API types (ComputeNode, VPod, SwitchNode, enums)
- `github.com/pensando/aicc-dev/venice/aifm/utils/checkpoint` — Checkpoint constants

### utils_test.go

**Constants**:
- `CONTROLLER_PKG_PATH = "/tmp/controller_pkg"` — Where controller debug package is extracted
- `AGENT_PKG_PATH = "/tmp/agent_pkg"` — Where agent debug package is extracted
- `failureLogsDir = "/tmp/restart_test_logs"` — Where failure log zips are archived

**Imports** (key packages):
- `github.com/cenkalti/backoff` — Exponential backoff for retries
- `github.com/pensando/aicc-dev/api/generated/cluster` — Cluster API types and enums
- `github.com/pensando/aicc-dev/venice/aifm/agents/protos` — `HealthInfo` struct for agent health
- `github.com/pensando/aicc-dev/venice/aifm/globals` — AIFM port calculation, `LogsDir`, `Unutilized` const
- `github.com/pensando/aicc-dev/venice/aifm/utils` — `ConstructSystemVPodName()`
- `github.com/pensando/aicc-dev/venice/aifm/utils/checkpoint` — Checkpoint types

---

## API Objects and Naming Conventions

| Entity | API Type | Name Pattern | Example |
|--------|----------|-------------|---------|
| Pod | `cluster.Pod` | `pod-{podID}` | `pod-1` |
| Compute Node | `cluster.ComputeNode` | `pod-1-{slotID}-ComputeTray` | `pod-1-0-ComputeTray` |
| Switch Node | `cluster.SwitchNode` | `pod-1-{slotID}-SwitchTray` | `pod-1-0-SwitchTray` |
| System VPod | `cluster.VPod` | `{podName}.system` | `pod-1.system` |
| User VPod | `cluster.VPod` | User-defined | `test-vpod` |

**API client usage pattern** (gRPC, not REST):

```go
apiServerClient.ClusterV1().ComputeNode().Get(ctx, &api.ObjectMeta{Name: "pod-1-0-ComputeTray"})
apiServerClient.ClusterV1().ComputeNode().List(ctx, &api.ListWatchOptions{})
apiServerClient.ClusterV1().ComputeNode().Decommission(ctx, &cluster.DecommissionRequest{...})
apiServerClient.ClusterV1().VPod().Get(ctx, &api.ObjectMeta{Name: "pod-1.system"})
apiServerClient.ClusterV1().VPod().Create(ctx, vpod)
apiServerClient.ClusterV1().VPod().Update(ctx, vpod)
apiServerClient.ClusterV1().VPod().Delete(ctx, vpod.ObjectMeta)
apiServerClient.ClusterV1().SwitchNode().Get(ctx, &api.ObjectMeta{Name: "pod-1-0-SwitchTray"})
apiServerClient.ClusterV1().SwitchNode().DrainSwitchNode(ctx, &cluster.DrainSwitchNodeRequest{...})
apiServerClient.ClusterV1().SwitchNode().DecommissionSwitchNode(ctx, &cluster.DecommissionSwitchNodeRequest{...})
apiServerClient.ClusterV1().Pod().List(ctx, &api.ListWatchOptions{})
```

**Key API enums**:
- `cluster.ComputeNodeStatus_ADMITTED`
- `cluster.ComputeNodeStatus_DECOMMISSION_FAILED`
- `cluster.ComputeNodePhase_Decommissioned`
- `cluster.MachineAction_Decommission`
- `cluster.SwitchNodeStatus_DRAINED`
- `cluster.SwitchNodeStatus_DECOMMISSIONED`
- `cluster.SwitchMachineAction_SwitchMachineActionDecommission`
- `cluster.VPodStatus_Online`
- `cluster.KindVPod`

**Admission phase state machine (ComputeNode)**:
```
ADMITTED ──(decommission, agent up)──────────> DECOMMISSIONED
ADMITTED ──(decommission, agent down)────────> DECOMMISSION_FAILED
DECOMMISSION_FAILED ──(force decommission)──> DECOMMISSIONED
```

**Admission phase state machine (SwitchNode)**:
```
ADMITTED ──(drain)────────────────────────────> DRAINED
DRAINED  ──(decommission)────────────────────> DECOMMISSIONED
```

---

## Checkpoint Definitions

All defined in `venice/aifm/utils/checkpoint/utils.go` as bitmask constants:

| Constant | Value | Location | Description |
|----------|-------|----------|-------------|
| `CheckpointTopoServiceNone` | `1<<0` | — | No-op sentinel |
| `CheckpointTopoServiceBeforeAddToStore` | `1<<1` | TopoService | Before adding topology object to store |
| `CheckpointTopoServiceAfterAddToStore` | `1<<2` | TopoService | After adding topology object to store |
| `CheckpointConfigManagerBeforeComputeNodeDecommission` | `1<<3` | ConfigManager | Before compute node decommission in `OnComputeTrayStatusChange` |
| `CheckpointConfigManagerAfterComputeNodeDecommission` | `1<<4` | ConfigManager | After compute node decommission submission |
| `CheckpointConfigManagerWithinComputeNodeDecommission` | `1<<5` | ConfigManager | Within `decommissionComputeNode`, before etcd write |
| `CheckpointConfigManagerBeforeSwitchNodeDecommission` | `1<<6` | ConfigManager | Before switch node decommission in `OnSwitchTrayStatusChange` |
| `CheckpointConfigManagerAfterSwitchNodeDecommission` | `1<<7` | ConfigManager | After switch node decommission submission |
| `CheckpointConfigManagerWithinSwitchNodeDecommission` | `1<<8` | ConfigManager | Within `decommissionSwitchNode`, before ASIC info erasure from etcd |
| `CheckpointNodeMgrBeforeSetVPODConfig` | `1<<9` | NodeManager | Before `SetVPODConfig` sent to node agent via mbus |
| `CheckpointNodeMgrAfterSetVPODConfig` | `1<<10` | NodeManager | After `SetVPODConfig` sent to node agent via mbus |
| `CheckpointSwitchMgrBeforeVLANOp` | `1<<11` | SwitchManager | Before VLAN create/update/delete during VPod lifecycle |
| `CheckpointSwitchMgrAfterVLANOp` | `1<<12` | SwitchManager | After VLAN create/update/delete during VPod lifecycle |

**How checkpoints are configured at runtime** (from `configureCheckpoint` in utils_test.go):

```go
payload := map[string]interface{}{"set": []int{int(checkpointType)}}
payloadBytes, _ := json.Marshal(payload)
port, _ := aifmglobals.GetAIFMCorePortForService(podID, aifmglobals.AifmCoreRest)
crashURL := fmt.Sprintf("http://%s:%s/debug/checkpoint", controllerIP, port)
resp, _ := http.Post(crashURL, "application/json", io.NopCloser(bytes.NewReader(payloadBytes)))
```

---

## Helper Functions Reference

### Process Lifecycle

| Function | Signature | Purpose |
|----------|-----------|---------|
| `startUnifiedController()` | `func() error` | Starts UC with `AIFM_DEBUG=1`, idempotent if already running |
| `stopUnifiedController()` | `func() error` | Graceful stop via `unified_controller.sh stop` |
| `startUnifiedNodeAgents(count)` | `func(int) error` | Starts N compute node agents with sequential slot IDs |
| `startUnifiedSwitchAgents(count)` | `func(int) error` | Starts N switch agents with sequential slot IDs |
| `stopUnifiedNodeAgents()` | `func() error` | Kills all node agents; uses `pkill` as fallback |
| `stopUnifiedSwitchAgents()` | `func() error` | Kills all switch agents; uses `pkill` as fallback |
| `stopUnifiedNodeAgent(slotID)` | `func(int) error` | Stops a specific node agent by slot |
| `stopUnifiedSwitchAgent(slotID)` | `func(int) error` | Stops a specific switch agent by slot |
| `startAll(nodes, switches)` | `func(int, int) error` | Starts UC + N node agents + M switch agents |
| `stopAll()` | `func() error` | Stops all agents, controller, and releases ports |
| `releaseAllPorts()` | `func() error` | Kills processes on AIFM core ports + minio port using `fuser -k` |
| `bootstrapAIFMCluster()` | `func() error` | Runs `bootstrap.py` with cluster name `testcluster`, pod `pod-1` |
| `writeAIFMConfig()` | `func() error` | Writes `/opt/amd/aifm/configs/config.yml` with controller IP |
| `installDependencies()` | `func() error` | Installs `musl`, `musl-dev` packages and creates musl symlink |
| `cleanEnvironment()` | `func() error` | Removes state dirs (etcd, logs, pki, data) but preserves configs |
| `cleanAll()` | `func() error` | `stopAll()` + `cleanEnvironment()` |
| `isProcessRunning(name)` | `func(string) bool` | Uses `pgrep -f` to check if a process is alive |

### Verification Functions

All verification functions return `bool` and are designed for use with Gomega's `Eventually()`:

| Function | Purpose |
|----------|---------|
| `verifyPodExists()` | Checks exactly 1 pod exists via API |
| `verifyNodeAgentConnectivity()` | Checks all node agents report `IsConnected=true` and include `controllerIP` in their controllers list via health endpoint (`http://localhost:{13000+slotID}/api/health`) |
| `verifySwitchAgentConnectivity()` | Same for switch agents (port = `13000 + 18 + slotID`) |
| `verifyComputeNodesRegistered()` | Checks API server has expected count of compute nodes |
| `verifySwitchNodesRegistered()` | Checks API server has expected count of switch nodes |
| `verifyComputeNodesInPodStatus()` | Checks all compute nodes appear in `pods[0].Status.Nodes` |
| `verifyScaleUpInfoPopulated()` | Checks all compute nodes have non-empty `Status.ScaleUpInfo.GpuInfo` |
| `verifyComputeNodeAdmissionPhase(slotID, phase)` | Checks a specific compute node is in the expected admission phase |
| `verifyComputeNodeDecommission()` | Alias for `verifyComputeNodeDecommissionBySlot(0)` |
| `verifyComputeNodeDecommissionBySlot(slotID)` | Checks `MachineAction=Decommission`, `AdmissionPhase=Decommissioned`, `GpuInfo` empty |
| `verifySwitchNodeAsicInfoPopulated(slotID)` | Checks switch node has non-empty `Status.AsicInfo.ASICs` |
| `verifySwitchNodeDrained(slotID)` | Checks `Status.AdmissionPhase == DRAINED` |
| `verifySwitchNodeDecommission(slotID)` | Checks `MachineAction=Decommission`, `AdmissionPhase=DECOMMISSIONED`, `AsicInfo` empty |
| `verifyGPUsRemovedFromVPodSpecAndStatus(vpodName, slotID)` | Checks no GPUs for given slot in VPod spec or status |
| `verifyVPODCreatedAndGPUsMoved()` | Checks `test-vpod` is Online with 8 GPUs and correct membership |
| `verifyVPODUpdatedAndGPUsUnutilized()` | Checks `test-vpod` is Online with 0 GPUs, nodes show `Unutilized` |
| `verifyVPODDeletedAndGPUsUnutilized()` | Checks `test-vpod` is NotFound, nodes show `Unutilized` |

### API Mutation Functions

| Function | Purpose |
|----------|---------|
| `disassociateGPUsFromSystemVPod(slotID)` | Removes GPUs for a slot from the system VPod spec via Update |
| `decommissionComputeNode(slotID)` | Calls `ComputeNode().Decommission()` with exponential backoff |
| `forceDecommissionComputeNode(slotID)` | Same but with `ForceDecommission: true` |
| `deleteComputeNode(slotID)` | Calls `ComputeNode().Delete()` |
| `drainSwitchNode(slotID)` | Calls `SwitchNode().DrainSwitchNode()` |
| `decommissionSwitchNode(slotID)` | Calls `SwitchNode().DecommissionSwitchNode()` with exponential backoff |
| `deleteSwitchNode(slotID)` | Calls `SwitchNode().Delete()` |
| `createVPOD()` | Creates `test-vpod` with GPUs from slots 0 and 1, parent `pod-1` |
| `updateVPOD()` | Updates `test-vpod` to have empty GPUs list |
| `deleteVPOD()` | Deletes `test-vpod` |

### Checkpoint and Recovery

| Function | Purpose |
|----------|---------|
| `configureCheckpoint(type, description)` | Sets a checkpoint flag via HTTP POST to controller debug endpoint |
| `waitForControllerReady()` | Waits for controller TCP port to accept connections; retries with restart if not ready within 1 minute; recreates API client after reconnect |
| `verifyControllerCrashed()` | `Eventually` checks that `unified_controller_debug` process is gone |
| `verifyControllerRecovery(validations...)` | Verifies pod exists, then runs additional validations |

### Cleanup and Logging

| Function | Purpose |
|----------|---------|
| `cleanComponentLogs()` | Removes and recreates the AIFM logs directory for test isolation |
| `collectFailureLogs(description)` | Archives all component logs into a zip named after the failed test |
| `systemVPodName()` | Returns `aifmutils.ConstructSystemVPodName("pod-1")` |
| `getIPAddress()` | Returns the first non-loopback IPv4 address of the machine |

---

## Writing New Test Cases

### Adding a New Checkpoint Test Entry

To add a new checkpoint-induced crash test:

1. **Define the checkpoint constant** in `venice/aifm/utils/checkpoint/utils.go` if it doesn't exist:
   ```go
   CheckpointMyNewCrashPoint CheckPoint = 1 << <next_bit>
   ```

2. **Instrument the controller code** with `checkpoint.Checkpoint(checkpoint.CheckpointMyNewCrashPoint)` at the desired crash location.

3. **Add an Entry** to the `DescribeTable` in `restart_test.go`:
   ```go
   Entry("My new crash scenario description",
       CheckpointTestCase{
           checkpoint:  aifmutils.CheckpointMyNewCrashPoint,
           description: "My new crash scenario description",
           preTriggerActions: []preTriggerAction{
               {
                   preTriggerActionFunction: func() error {
                       return startUnifiedNodeAgents(2)
                   },
                   description: "start node agents",
               },
               // ... more setup steps
           },
           triggerAction: func() error {
               // The action that will hit the checkpoint and crash the controller
               return someAPICall()
           },
           additionalValidations: []ValidationFunc{
               {
                   validationFunction: myVerificationFunc,
                   description:        "State should be consistent after recovery",
               },
           },
           cleanUpActions: []cleanUpAction{
               {
                   cleanUpActionFunction: func() error {
                       return stopUnifiedNodeAgent(0)
                   },
                   description: "clean up agents",
               },
           },
       },
   ),
   ```

4. **Build debug packages** (`make build-debug-all`) so the new checkpoint is compiled in.

### Adding a New Self-Contained Context

For tests that don't fit the checkpoint table pattern:

```go
Context("when <scenario description>", func() {
    It("should <expected behavior>", func() {
        // 1. Start required components
        err := startUnifiedController()
        Expect(err).ToNot(HaveOccurred())
        defer func() {
            stopAll()
        }()

        // 2. Setup
        By("setting up the test scenario", func() {
            // ...
        })

        // 3. Action
        By("performing the test action", func() {
            // ...
        })

        // 4. Verification
        By("verifying the expected state", func() {
            Eventually(myVerification, 2*time.Minute, 5*time.Second).Should(BeTrue())
        })
    })
})
```

**Rules**:
- Each `It()` must start all required components
- Each `It()` must clean up (use `defer stopAll()`)
- Use `By()` for narrative steps
- Use `Eventually()` with timeouts for async verification
- Use `Consistently()` for negative assertions (state should NOT change)

### Adding a New Verification Helper

Add to `utils_test.go`. Follow the existing pattern:

```go
func verifyMyCondition() bool {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    obj, err := apiServerClient.ClusterV1().SomeResource().Get(ctx, &api.ObjectMeta{Name: "name"})
    if err != nil {
        logger.Errorf("Failed to get resource: %v", err)
        return false
    }

    if obj.Status.SomeField != expectedValue {
        logger.Infof("Not ready yet: got %s, want %s", obj.Status.SomeField, expectedValue)
        return false
    }

    logger.Infof("Condition met for resource")
    return true
}
```

**Pattern rules**:
- Return `bool`, not `error` — Gomega `Eventually` expects `bool`
- Log informational messages with `logger.Infof` for debugging
- Log errors with `logger.Errorf` for unexpected failures
- Always use `context.WithCancel` and defer cancel
- Return `false` (not panic) on transient failures — `Eventually` will retry

---

## Debugging Failures

### Step-by-step debugging approach

1. **Read the Ginkgo output** — Look for the `[FAIL]` marker and the `By()` step where it failed.

2. **Check `/tmp/restart_test.log`** — Contains detailed logger output with timing and state info.

3. **Check failure log archives** — `/tmp/restart_test_logs/<test_name>.zip` contains component logs from the moment of failure.

4. **Check if processes are stuck**:
   ```bash
   ps aux | grep -E 'unified_controller|unified_agent' | grep -v grep
   ```

5. **Check port conflicts**:
   ```bash
   sudo fuser 9003/tcp 60009/tcp 13000/tcp 13001/tcp 13018/tcp
   ```

6. **Manual cleanup if state is corrupted**:
   ```bash
   sudo pkill -f unified_controller_debug
   sudo pkill -f unified_agent_debug
   sudo rm -rf /etc/pensando/ /var/lib/pensando /tmp/aifm /var/lib/etcd/ \
     /var/log/pensando /opt/amd/aifm/logs /opt/amd/aifm/sysconfig \
     /opt/amd/aifm/pki /opt/amd/aifm/data
   ```

7. **Run a single failing test**:
   ```bash
   export GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore
   cd ~/src/github.com/pensando/aicc-dev/test/integ/aifm/restart
   ginkgo -v --focus "<exact test description>"
   ```

### Common failure patterns

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| "Should bootstrap AIFM cluster" fails | Stale etcd state or port conflict | Run manual cleanup, then retry |
| "All node agents should be connected" times out | Agent binary not at `/tmp/agent_pkg/` | Re-extract debug packages |
| "Controller should be listening on port" | Controller crashed during startup | Check `/opt/amd/aifm/logs/` for crash logs |
| "ScaleUpInfo should be populated" times out | Agent can't communicate with controller | Verify controller IP matches agent config |
| "unified_controller_debug process should have crashed" fails | Checkpoint not compiled in | Rebuild with `make build-debug-all` (needs `aifm_debug` tag) |
| Tests pass locally but fail in CI | Missing musl dependency | `installDependencies()` should handle this; check CI logs |

---

## Common Pitfalls

1. **Forgetting `GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore`** — Tests will fail with protobuf registration errors.

2. **Using non-debug packages** — Normal `unified_controller` doesn't have checkpoint injection. Must use `unified_controller_debug` from `make build-debug-all`.

3. **Stale processes from a previous run** — Always check for and kill leftover `unified_controller_debug` and `unified_agent_debug` processes.

4. **Port conflicts** — The suite uses fixed ports (9003, 13000+, 60000+). Other AIFM processes on the same VM will conflict.

5. **Editing `XEntry` tests without enabling them** — `XEntry` tests are skipped. Change to `Entry` to run them.

6. **Missing musl library** — The debug binaries need `musl`. The suite installs it automatically but requires `sudo` without password.

7. **Not rebuilding after checkpoint changes** — If you add/modify checkpoints in `venice/aifm/utils/checkpoint/utils.go`, you must rebuild debug packages.

8. **Test isolation violation** — Each `It()` block must be fully independent. Don't rely on state from a previous test.

9. **Exponential backoff in decommission functions** — The `decommissionComputeNode` and `decommissionSwitchNode` functions use exponential backoff (up to 2 minutes) when fetching node state. If ScaleUpInfo/AsicInfo is not populated, they retry. This is intentional for robustness.

10. **`waitForControllerReady` recreates the API client** — After a controller restart, the gRPC connection must be re-established. This function handles it.

---

## Quick Reference Commands

| Action | Command |
|--------|---------|
| Build debug packages | `cd ~/src/github.com/pensando/aicc-dev && make build-debug-all` |
| Build UC debug only | `make build-unified-controller-debug` |
| Build UA debug only | `make build-unified-agent-debug` |
| Extract UC debug | `tar -xvf ./bin/unified_controller_debug_package.tar -C /tmp` |
| Extract UA debug | `tar -xvf ./bin/unified_agent_debug_package.tar -C /tmp` |
| Run all tests | `export GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore && cd test/integ/aifm/restart && ginkgo -v` |
| Run via CI Makefile | `cd test/ci_targets/aifm && make restart-test` |
| Run single test | `ginkgo -v --focus "test description substring"` |
| Run with timeout | `ginkgo -v -timeout 60m` |
| View test log | `tail -f /tmp/restart_test.log` |
| View failure logs | `ls /tmp/restart_test_logs/` |
| Kill stuck processes | `sudo pkill -f unified_controller_debug && sudo pkill -f unified_agent_debug` |
| Check running procs | `ps aux \| grep -E 'unified_controller\|unified_agent' \| grep -v grep` |
| Full environment clean | `sudo rm -rf /etc/pensando/ /var/lib/pensando /tmp/aifm /var/lib/etcd/ /var/log/pensando /opt/amd/aifm/logs /opt/amd/aifm/sysconfig /opt/amd/aifm/pki /opt/amd/aifm/data` |
| Enable pending test | Change `XEntry(` to `Entry(` in `restart_test.go` |
| Disable active test | Change `Entry(` to `XEntry(` in `restart_test.go` |

---

## Instructions for AI Assistants

When this skill is invoked:

1. **Identify the user's intent**: building, running, debugging, or extending the restart test suite.

2. **For building**: Use `make build-debug-all` from `~/src/github.com/pensando/aicc-dev`. Monitor the Docker build (10–20 min). Verify artifacts exist in `bin/`.

3. **For running**: Ensure debug packages are extracted to `/tmp`. Set `GOLANG_PROTOBUF_REGISTRATION_CONFLICT=ignore`. Use `ginkgo -v` or `make restart-test`. Monitor `/tmp/restart_test.log` for progress.

4. **For debugging**: Read `/tmp/restart_test.log` and check `/tmp/restart_test_logs/` for zipped failure logs. Check for stuck processes. Use `--focus` to isolate failing tests.

5. **For extending**: Follow the `CheckpointTestCase` pattern for checkpoint tests. Follow the self-contained `Context/It` pattern for non-checkpoint tests. Always add verification helpers to `utils_test.go` following the `bool`-returning pattern.

6. **For understanding test output**: Ginkgo output uses `[PASS]`, `[FAIL]`, `[PENDING]` markers. `By()` steps appear as indented sub-steps. `Eventually` retries are not shown in output — only the final result.

7. **Key files to read first**:
   - `test/integ/aifm/restart/restart_test.go` — Test specifications
   - `test/integ/aifm/restart/utils_test.go` — All helper functions
   - `test/integ/aifm/restart/restart_suite_test.go` — Suite setup/teardown
   - `venice/aifm/utils/checkpoint/utils.go` — Checkpoint definitions
