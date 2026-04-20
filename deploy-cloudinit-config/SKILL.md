---
name: deploy-cloudinit-config
description: >-
  Deploy cloud-init config files (k8s-config.yml, slurm-config.yml, centos-config.yml)
  to an AICC controller by replacing remote files via SSH/SCP. Use when the user wants
  to update cloud-init configs on a controller, deploy cloudinit config, push config
  to controller, replace k8s-config or slurm-config on a remote controller, or
  mentions deploy-cloudinit-config.
---

# Deploy Cloud-Init Config to Controller

## Overview

Replaces cloud-init config files on a remote AICC controller with the latest
versions from the local repo at `venice/ctrler/orchhub/statemgr/`.

Source configs in the repo:
- `venice/ctrler/orchhub/statemgr/k8s-config.yml`
- `venice/ctrler/orchhub/statemgr/slurm-config.yml`
- `venice/ctrler/orchhub/statemgr/centos-config.yml`

## Step 1: Gather Information

Ask the user for:

1. **Controller IP** (required): The IP address of the AICC controller to deploy to.
2. **Username** (required): SSH username for the controller.
3. **Password** (required): SSH password for the controller.

Use the AskQuestion tool if available, otherwise ask conversationally.

## Step 2: Determine Which Configs to Deploy

The user may ask to deploy specific configs. Determine which source files to deploy:

- **"deploy k8s config"** → deploy `k8s-config.yml` to k8s destinations only.
- **"deploy slurm config"** → deploy `slurm-config.yml` to slurm destinations only.
- **"deploy k8s, slurm config"** → deploy both (default behavior of the script).
- **"deploy centos config"** → deploy `centos-config.yml` to ALL destinations
  (both k8s AND slurm). CentOS config replaces both because the orchestrator
  currently only selects k8s or slurm templates — centos-config.yml must be
  placed at those paths so it gets picked up regardless of scheduler type.

## Step 3: Deploy Config Files

### For k8s and/or slurm configs

Run the deploy script directly:

```bash
bash ~/.cursor/skills/deploy-cloudinit-config/scripts/deploy-config.sh <CONTROLLER_IP> <USERNAME> <PASSWORD>
```

The script deploys to these destinations:

| Local source file | Remote destination paths |
|---|---|
| `k8s-config.yml` | `/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/733/fs/target/etc/pensando/k8s-config.yml` |
| `k8s-config.yml` | `/etc/pensando/configs/pen-orchhub/k8s-cloudinit-config.yml` |
| `k8s-config.yml` | `/etc/pensando/pen-orchhub/k8s-cloudinit-config.yml` |
| `slurm-config.yml` | `/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/733/fs/target/etc/pensando/slurm-config.yml` |
| `slurm-config.yml` | `/etc/pensando/configs/pen-orchhub/slurm-cloudinit-config.yml` |
| `slurm-config.yml` | `/etc/pensando/pen-orchhub/slurm-cloudinit-config.yml` |

### For centos-config

Do NOT run the script. Instead, deploy manually using SSH with sudo. The
centos-config.yml replaces BOTH k8s and slurm config content at all 6 destinations:

```bash
REPO_DIR="$(git rev-parse --show-toplevel)/venice/ctrler/orchhub/statemgr"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
HOST="<USERNAME>@<CONTROLLER_IP>"

# 1. SCP centos-config.yml to /tmp on the controller
sshpass -p <PASSWORD> scp $SSH_OPTS "$REPO_DIR/centos-config.yml" "$HOST:/tmp/"

# 2. SSH in and sudo cp to all 6 destinations
sshpass -p <PASSWORD> ssh $SSH_OPTS $HOST "
SNAP='/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/733/fs/target/etc/pensando'

echo '<PASSWORD>' | sudo -S cp /tmp/centos-config.yml /etc/pensando/configs/pen-orchhub/k8s-cloudinit-config.yml
echo '<PASSWORD>' | sudo -S cp /tmp/centos-config.yml /etc/pensando/configs/pen-orchhub/slurm-cloudinit-config.yml
echo '<PASSWORD>' | sudo -S cp /tmp/centos-config.yml /etc/pensando/pen-orchhub/k8s-cloudinit-config.yml
echo '<PASSWORD>' | sudo -S cp /tmp/centos-config.yml /etc/pensando/pen-orchhub/slurm-cloudinit-config.yml
echo '<PASSWORD>' | sudo -S cp /tmp/centos-config.yml \"\$SNAP/k8s-config.yml\"
echo '<PASSWORD>' | sudo -S cp /tmp/centos-config.yml \"\$SNAP/slurm-config.yml\"

ls -la /etc/pensando/configs/pen-orchhub/k8s-cloudinit-config.yml
ls -la /etc/pensando/configs/pen-orchhub/slurm-cloudinit-config.yml
ls -la /etc/pensando/pen-orchhub/k8s-cloudinit-config.yml
ls -la /etc/pensando/pen-orchhub/slurm-cloudinit-config.yml
sudo ls -la \"\$SNAP/k8s-config.yml\"
sudo ls -la \"\$SNAP/slurm-config.yml\"

rm -f /tmp/centos-config.yml
"
```

**Important**: File names at the destination remain unchanged; only the content
is replaced with centos-config.yml.

## Step 4: Verify

After deployment, check the output for errors. Report success/failure with a
table showing each destination and its status.

If SSH/SCP fails (permission denied, unreachable, etc.), suggest:
- Verify the controller IP, username, and password are correct
- Check network connectivity to the controller
- Ensure `sshpass` is installed (`sudo apt install sshpass` or `sudo yum install sshpass`)

## Notes

- The deploy script uses direct SCP which only works if the SSH user has write
  permission to the destination paths. If the user is non-root (e.g. `vm`), the
  script will fail with "Permission denied". In that case, use the manual sudo
  approach shown in the centos-config section above (SCP to /tmp, then sudo cp).
- The snapshot number `733` in the containerd path is hardcoded. If the snapshot
  number changes on the controller, update the script or find the correct one:
  `sudo find /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/ -path '*/etc/pensando' -type d`
- The containerd snapshot path requires sudo even to check if it exists. The
  deploy script's `test -d` check will incorrectly report the directory as
  missing for non-root users.
