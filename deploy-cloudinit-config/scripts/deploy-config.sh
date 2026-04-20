#!/bin/bash
set -euo pipefail

CONTROLLER_IP="${1:?Usage: $0 <CONTROLLER_IP> <USERNAME> <PASSWORD>}"
SSH_USER="${2:?Usage: $0 <CONTROLLER_IP> <USERNAME> <PASSWORD>}"
SSH_PASS="${3:?Usage: $0 <CONTROLLER_IP> <USERNAME> <PASSWORD>}"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

if ! command -v sshpass &>/dev/null; then
    echo "sshpass not found, attempting to install..."
    if command -v apt &>/dev/null; then
        sudo apt install -y sshpass
    elif command -v yum &>/dev/null; then
        sudo yum install -y sshpass
    else
        echo "ERROR: sshpass is not installed and could not auto-install. Install it manually."
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_CONFIG_DIR="$(cd "$SCRIPT_DIR/../../../../src/github.com/pensando/aicc-dev-1.0-C/venice/ctrler/orchhub/statemgr" 2>/dev/null && pwd)" || true

if [ -z "$REPO_CONFIG_DIR" ] || [ ! -d "$REPO_CONFIG_DIR" ]; then
    REPO_CONFIG_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/venice/ctrler/orchhub/statemgr" || true
fi

if [ -z "$REPO_CONFIG_DIR" ] || [ ! -d "$REPO_CONFIG_DIR" ]; then
    echo "ERROR: Cannot locate repo config directory. Run from within the aicc-dev repo."
    exit 1
fi

K8S_SRC="$REPO_CONFIG_DIR/k8s-config.yml"
SLURM_SRC="$REPO_CONFIG_DIR/slurm-config.yml"

for f in "$K8S_SRC" "$SLURM_SRC"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Source file not found: $f"
        exit 1
    fi
done

K8S_TARGETS=(
    "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/733/fs/target/etc/pensando/k8s-config.yml"
    "/etc/pensando/configs/pen-orchhub/k8s-cloudinit-config.yml"
    "/etc/pensando/pen-orchhub/k8s-cloudinit-config.yml"
)

SLURM_TARGETS=(
    "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/733/fs/target/etc/pensando/slurm-config.yml"
    "/etc/pensando/configs/pen-orchhub/slurm-cloudinit-config.yml"
    "/etc/pensando/pen-orchhub/slurm-cloudinit-config.yml"
)

do_ssh() {
    sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$CONTROLLER_IP" "$@"
}

do_scp() {
    sshpass -p "$SSH_PASS" scp $SSH_OPTS "$@"
}

echo "=========================================="
echo "Deploying cloud-init configs to controller"
echo "Controller: $CONTROLLER_IP"
echo "User:       $SSH_USER"
echo "K8s source: $K8S_SRC"
echo "Slurm source: $SLURM_SRC"
echo "=========================================="

echo ""
echo "--- Verifying SSH connectivity ---"
if ! do_ssh "echo 'SSH OK'"; then
    echo "ERROR: Cannot SSH to $SSH_USER@$CONTROLLER_IP"
    exit 1
fi

ERRORS=0

deploy_file() {
    local src="$1"
    local dest="$2"
    local label="$3"

    echo ""
    echo "--- Deploying $label -> $dest ---"

    if do_ssh "test -d '$(dirname "$dest")'"; then
        if do_scp "$src" "$SSH_USER@$CONTROLLER_IP:$dest"; then
            echo "OK: $dest updated"
        else
            echo "FAILED: Could not copy to $dest"
            ERRORS=$((ERRORS + 1))
        fi
    else
        echo "SKIPPED: Directory $(dirname "$dest") does not exist on controller"
        ERRORS=$((ERRORS + 1))
    fi
}

for target in "${K8S_TARGETS[@]}"; do
    deploy_file "$K8S_SRC" "$target" "k8s-config.yml"
done

for target in "${SLURM_TARGETS[@]}"; do
    deploy_file "$SLURM_SRC" "$target" "slurm-config.yml"
done

echo ""
echo "=========================================="
if [ "$ERRORS" -eq 0 ]; then
    echo "SUCCESS: All config files deployed"
else
    echo "COMPLETED WITH $ERRORS ERROR(S)"
    echo "Check output above for details."
fi
echo "=========================================="

exit $ERRORS
