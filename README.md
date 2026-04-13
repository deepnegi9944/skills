# Cursor Agent Skills

Custom skills for Cursor AI agent. Each skill teaches the agent how to perform a specific task automatically.

## Installation

Clone into your Cursor skills directory:

```bash
git clone git@github.com:deepnegi9944/skills.git ~/.cursor/skills
```

If you already have a `~/.cursor/skills` directory, clone elsewhere and copy:

```bash
git clone git@github.com:deepnegi9944/skills.git /tmp/skills
cp -r /tmp/skills/*/ ~/.cursor/skills/
```

Once installed, Cursor automatically discovers skills from `~/.cursor/skills/` and uses them when relevant.

## Available Skills

### maas-image-upload

Login to a MAAS server and upload custom OS images (CentOS, Ubuntu, etc.) as boot resources.

**You provide:** MAAS URL, API key, and image path (rootfs directory or `.tar.gz`).

| Trigger | What It Does |
|---------|--------------|
| "Login to MAAS" | Logs into MAAS CLI with API key or username/password |
| "Upload image to MAAS" | Repacks rootfs into tarball (if needed) and uploads to MAAS |
| "List MAAS boot resources" | Lists all boot resources via `maas shell` |
| "Check image sync status" | Monitors rack controller download progress until complete |

### run-restart-test

Build and run the AIFM restart integration tests in the `pensando/aicc-dev` repo.

| Trigger | What It Does |
|---------|--------------|
| "Run the restart tests" | Extracts debug packages, builds test binary, and runs all tests via Ginkgo |
| "Build restart-test.bin" | Compiles the test binary with correct Go flags to `/tmp/restart-test.bin` |
| "Run a specific restart test" | Runs a single test by name using `-ginkgo.focus` |
