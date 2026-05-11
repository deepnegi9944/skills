---
name: rebase-branch-on-parent
description: Rebase a feature branch onto the latest parent branch (main or 1.0-C) in the aicc-dev repo. Stashes any working changes, fetches and pulls the parent, then rebases the feature branch on top. Use when the user asks to rebase a branch, sync a branch with main, sync a branch with 1.0-C, update a branch on top of latest, or mentions "rebase".
---

# Rebase Branch on Parent

Sync a feature branch with the latest parent branch (`main` or `1.0-C`) using rebase. Always stash uncommitted changes first to keep the working tree clean during the operation.

## Required inputs

Always ask the user for both before running anything:

1. **Feature branch to rebase** (e.g. `logs`, `aifm-763`, `restart_test`)
   - Use AskQuestion with a free-form prompt OR list local branches via `git branch` if the user is unsure.
2. **Parent branch** — present exactly these two options via AskQuestion:
   - `main`
   - `1.0-C`

Do not assume defaults. Always ask both questions before running git commands.

## Workflow

Run from the repo root (`~/src/github.com/pensando/aicc-dev`). Execute steps sequentially; stop and report if any step fails.

```
- [ ] Step 1: Stash any working changes with a message
- [ ] Step 2: Checkout the parent branch
- [ ] Step 3: Fetch from origin
- [ ] Step 4: Pull (fast-forward) the parent
- [ ] Step 5: Checkout the feature branch
- [ ] Step 6: Rebase the feature branch onto origin/<parent>
- [ ] Step 7: Pop the stash created in Step 1 (only if one was created)
```

### Step 1: Stash working changes

```bash
git stash -m "cleanup"
```

If `git status` shows nothing to stash, skip this step **and** skip Step 7. Track whether a stash was actually created so Step 7 knows whether to run.

### Step 2: Checkout parent

```bash
git checkout <parent>     # main or 1.0-C
```

### Step 3 & 4: Fetch and pull

```bash
git fetch origin
git pull
```

The pull must be a clean fast-forward. If it is not, stop and report to the user.

### Step 5: Checkout feature branch

```bash
git checkout <feature-branch>
```

### Step 6: Rebase

```bash
git rebase origin/<parent>
```

If the rebase produces conflicts, stop immediately, show the output, and let the user resolve. Do **not** run `git rebase --abort` or `--continue`, and do **not** run Step 7, without explicit user confirmation.

### Step 7: Pop the stash

Only run if Step 1 actually created a stash and the rebase in Step 6 succeeded:

```bash
git stash pop
```

If `git stash pop` produces conflicts, stop and report — do not attempt to resolve automatically.

## After completion

Report:
- Whether a stash was created (and its message)
- The parent commit range pulled (e.g. `456617fd6..95cc5644a`)
- Rebase result (`Successfully rebased and updated refs/heads/<feature>` or conflict status)
- Stash pop result (applied cleanly, conflicted, or skipped because no stash existed)

## Example invocation

User: "rebase my branch"

Agent:
1. Asks: "Which feature branch should I rebase?"
2. Asks: "Which parent branch?" with options `main` and `1.0-C`
3. Runs the 6-step workflow above and reports.
