---
name: aicc-dev-prompt-guide
description: >-
  Help the user write better prompts for the AICC-DEV / AIFM codebase.
  Rewrite or improve vague prompts into precise, actionable instructions
  with file paths, object names, and expected behavior. Use when the user
  asks to improve a prompt, rephrase a request, or when a prompt is
  ambiguous. Also use when the user says "improve my prompt", "rewrite
  this prompt", "make this clearer", or "help me ask better questions".
---

# AICC-DEV Prompt Guide

This skill helps you write precise, actionable prompts for working with the AICC-DEV / AIFM codebase. It transforms vague requests into structured prompts that give the agent the right context to act on the first try.

## Why Prompts Matter in This Codebase

The AICC-DEV repo is large (~3M+ lines across Go, Proto, Python, Ansible, TypeScript, Makefiles, YAML). Vague prompts cause the agent to spend many tool calls exploring before it can act. A precise prompt saves 5-10 minutes per interaction.

## Quick Reference: Prompt Patterns

### Pattern 1: Bug Fix / Test Failure

**Template:**
```
[Test name or error message]
@[log file path] — [what the log shows or line range]
Logs are at [directory]. Unzip and check them.
[Optional: PR or commit that introduced the regression]
```

**Example (good):**
```
"TopoService after AddToStore during Update of VPOD" test is failing.
@/tmp/restart_test.log — look at lines 540-640
Failure logs are at /tmp/restart_test_logs/failure/ — unzip and check.
Started failing after rebasing PR #3364.
```

**Example (bad):**
```
test is failing
```

### Pattern 2: Code Change / Rename / Refactor

**Template:**
```
[What to change]: rename/add/remove/refactor [old] -> [new]
Scope: [which files/packages/layers]
[Optional: Jira ticket for context]
```

**Example (good):**
```
Rename aifm-controller -> afm-controller across the codebase.
This covers: systemd service names, Docker image names, Makefile targets,
Ansible playbooks, Go constants, and docs.
Jira: AIFM-529
```

**Example (bad):**
```
rename aifm stuff
```

### Pattern 3: Explain Code

**Template:**
```
@[file path]:[line number or range] — explain [what specifically]
```

**Example (good):**
```
@api/hooks/apiserver/cluster.go:4421 — explain what this pre-commit hook
does and how ReconfigureDataFabric flows through the system.
```

**Example (bad):**
```
explain this code
```

### Pattern 4: Review / Audit

**Template:**
```
@[file path] — review for [specific concerns: correctness, duplication,
missing cleanup, race conditions, etc.]
```

**Example (good):**
```
@test/integ/aifm/restart/restart_test.go — review this file for:
duplicate test entries, missing cleanup actions, broken pre-trigger
setups, and any format specifier mismatches in utils_test.go.
```

### Pattern 5: Terminal / Process Operations

**Template:**
```
@[terminal file path]:[line range] — [action: kill, stop, check, diagnose]
```

**Example (good):**
```
@terminals/3.txt:13-16 — bring down these processes
```

### Pattern 6: Build / Run

**Template:**
```
Run [make target or test command].
[Optional: environment, flags, or context]
```

**Example (good):**
```
Run the restart integration tests. Debug packages are already extracted
to /tmp. Focus on "TopoService before AddToStore during SwitchNode
decommission".
```

### Pattern 7: Investigate with Logs

**Template:**
```
Check @[log file]:[line range] — [what to look for]
Detailed logs are at [path]. Unzip and check [specific files].
```

---

## Key Context to Include

When writing prompts for this codebase, the agent works faster when you provide:

| Context | Why It Helps | Example |
|---------|-------------|---------|
| **File path + line** | Skips exploration | `@api/hooks/apiserver/cluster.go:3067` |
| **API object names** | Disambiguates objects | `pod-1-0-ComputeTray`, `pod-1.system`, `test-vpod` |
| **Test name (Ginkgo)** | Enables `--focus` | `"TopoService after AddToStore during Update of VPOD"` |
| **Log file location** | Directs investigation | `/tmp/restart_test.log`, `/tmp/restart_test_logs/failure/` |
| **PR/commit** | Narrows regression scope | `PR #3364`, `commit aed7d41` |
| **Jira ticket** | Provides requirements | `AIFM-529` |
| **Package name** | Scopes search | `venice/aifm/config_mgr/statemgr/cluster/` |
| **Error message** | Direct grep target | `"Failed pre conditions"`, `"parent pod pod-1 has no registered nodes"` |
| **Make target** | Specifies build | `make build-debug-all`, `make restart-test` |

## AIFM Domain Terms

Use these precise terms instead of vague descriptions:

| Say This | Not This |
|----------|----------|
| ComputeNode slot 0 | the server |
| SwitchNode slot 0 | the switch |
| system VPod `pod-1.system` | the default vpod |
| checkpoint `CheckpointTopoServiceBeforeAddToStore` | crash point |
| `ScaleUpInfo.GpuInfo` | gpu info |
| `AdmissionPhase` | node state |
| `VPoDMembership` | gpu assignment |
| precommit hook | validation |
| toposervice | topo database |
| config_mgr / configmgr | config manager |
| `decommissionComputeNode(0)` | decommission |
| `disassociateGPUsFromSystemVPod(1)` | remove gpus |
| unified_controller_debug | controller |
| unified_agent_debug | agent |

## How the Agent Uses Your Prompt

1. **File paths** → Agent reads them directly (no search needed)
2. **Error messages** → Agent greps for the source
3. **Log file + lines** → Agent reads the exact range
4. **API object names** → Agent knows the naming pattern (e.g., `pod-{podID}-{slotID}-ComputeTray`)
5. **PR/commit** → Agent runs `git show` or `gh pr view` to find changed files
6. **Jira ticket** → Agent fetches via MCP Atlassian tool

## Instructions for the Agent

When this skill is invoked:

1. **Read the user's original prompt** and identify which pattern it matches (or should match).
2. **Rewrite it** using the appropriate template above, filling in missing context from:
   - Currently open files in the IDE
   - Recent terminal output
   - The CLAUDE.md files for relevant packages
   - The user's recent conversation history
3. **Present the improved prompt** to the user and explain what was added and why.
4. **Ask if they want to proceed** with the improved version or adjust it.

If the user's prompt is already precise (has file paths, object names, and clear action), tell them it's already good and proceed directly.
