#!/bin/bash

set -e

echo "=========================================="
echo "MicroK8s Installation Script for Ubuntu"
echo "=========================================="
echo ""

# Check if running on Ubuntu
if [ ! -f /etc/os-release ]; then
    echo "❌ Error: Cannot detect OS. This script is designed for Ubuntu."
    exit 1
fi

source /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    echo "❌ Error: This script is designed for Ubuntu. Detected: $ID"
    exit 1
fi

echo "✅ Detected Ubuntu $VERSION"
echo ""

# ==============================
# Step 0: Prepare data disk for /var/snap (recommended for microk8s)
# ==============================
DATA_DEV="/dev/sdb1"
MOUNT_POINT="/var/snap"

echo "Step 0: Preparing data disk for ${MOUNT_POINT} (${DATA_DEV})..."

# Check if device exists
if [ -b "$DATA_DEV" ]; then
    echo "✅ Found data disk: $DATA_DEV"
    
    # Get UUID (empty if no filesystem)
    DATA_UUID="$(sudo blkid -s UUID -o value "$DATA_DEV" 2>/dev/null || true)"
    DATA_FSTYPE="$(sudo blkid -s TYPE -o value "$DATA_DEV" 2>/dev/null || true)"
    
    # If no filesystem, format it
    if [ -z "$DATA_FSTYPE" ]; then
        echo "⚠️  No filesystem on $DATA_DEV. Formatting as ext4..."
        read -p "This will erase all data on $DATA_DEV. Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping disk formatting. Continuing without mounting $DATA_DEV..."
        else
            sudo mkfs.ext4 -F "$DATA_DEV"
            DATA_UUID="$(sudo blkid -s UUID -o value "$DATA_DEV")"
            DATA_FSTYPE="ext4"
        fi
    fi
    
    # If we have a filesystem, proceed with mounting
    if [ -n "$DATA_FSTYPE" ]; then
        # Stop snapd to avoid /var/snap being busy
        echo "Stopping snapd temporarily..."
        sudo systemctl stop snapd.service 2>/dev/null || true
        sudo systemctl stop snapd.socket 2>/dev/null || true
        
        # Ensure mount point exists
        sudo mkdir -p "$MOUNT_POINT"
        
        # If /var/snap is not a mountpoint, back it up and clean it
        if ! mountpoint -q "$MOUNT_POINT"; then
            if [ -d "$MOUNT_POINT" ] && [ "$(ls -A $MOUNT_POINT)" ]; then
                echo "Backing up existing ${MOUNT_POINT} contents..."
                sudo mv "$MOUNT_POINT" "${MOUNT_POINT}.backup.$(date +%Y%m%d_%H%M%S)"
                sudo mkdir -p "$MOUNT_POINT"
            fi
        fi
        
        # Update /etc/fstab entry (idempotent)
        FSTAB_LINE="UUID=${DATA_UUID} ${MOUNT_POINT} ext4 defaults,nofail 0 2"
        echo "Ensuring /etc/fstab has: $FSTAB_LINE"
        
        # Remove any previous /var/snap entries, then append the correct one
        sudo sed -i '\|[[:space:]]/var/snap[[:space:]]|d' /etc/fstab
        echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
        
        # Reload systemd and mount
        sudo systemctl daemon-reload
        sudo mount -a
        
        # Verify
        if mountpoint -q "$MOUNT_POINT"; then
            echo "✅ Mounted ${DATA_DEV} to ${MOUNT_POINT}"
            df -h | grep -E "(/var/snap|Filesystem)" || true
        else
            echo "⚠️  Warning: ${MOUNT_POINT} is not mounted. Continuing anyway..."
        fi
        
        # Start snapd back
        echo "Starting snapd back..."
        sudo systemctl start snapd.socket 2>/dev/null || true
        sudo systemctl start snapd.service 2>/dev/null || true
    fi
else
    echo "⚠️  Data disk $DATA_DEV not found. Skipping disk mount."
    echo "   MicroK8s will use default storage location."
fi

echo ""

# Check if microk8s is already installed
MICROK8S_INSTALLED=false
if command -v microk8s &> /dev/null; then
    MICROK8S_INSTALLED=true
    echo "⚠️  MicroK8s is already installed."
    sudo microk8s version
    echo ""
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing MicroK8s installation..."
        sudo snap remove microk8s
        MICROK8S_INSTALLED=false
    else
        echo "Skipping installation, will configure existing MicroK8s..."
    fi
fi

if [ "$MICROK8S_INSTALLED" = false ]; then
    echo "Step 1: Installing MicroK8s via snap..."
    sudo snap install microk8s --classic --channel=1.28/stable
else
    echo "Step 1: Using existing MicroK8s installation..."
fi

echo ""
echo "Step 2: Adding current user to microk8s group..."
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube || true

echo ""
echo "Step 3: Waiting for MicroK8s to be ready..."
sudo microk8s status --wait-ready

echo ""
echo "Step 4: Enabling essential addons..."
sudo microk8s enable dns
sudo microk8s enable hostpath-storage
sudo microk8s enable helm3

echo ""
echo "Step 5: Creating kubectl and helm symlinks..."
sudo snap alias microk8s.kubectl kubectl
sudo snap alias microk8s.helm3 helm

echo ""
echo "Step 6: Configuring kubectl access..."
mkdir -p ~/.kube
sudo microk8s config > ~/.kube/config
chmod 600 ~/.kube/config

echo ""
echo "Step 7: Verifying installation..."
echo "kubectl version:"
sudo microk8s kubectl version --client --short 2>/dev/null || sudo microk8s kubectl version --client
echo ""
echo "helm version:"
sudo microk8s helm3 version --short 2>/dev/null || sudo microk8s helm3 version

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "✅ kubectl and helm are now available as system commands (via snap aliases)"
echo ""
echo "📝 Standard Kubernetes Commands (work on both Ubuntu and macOS):"
echo "  kubectl get nodes            # List nodes"
echo "  kubectl get pods -A          # List all pods"
echo "  helm version                 # Check Helm version"
echo ""
echo "🔧 MicroK8s-specific Commands:"
echo "  microk8s status              # Check MicroK8s status"
echo "  microk8s enable <addon>      # Enable addon (dns, storage, helm3, etc.)"
echo "  microk8s disable <addon>     # Disable addon"
echo "  microk8s start               # Start MicroK8s"
echo "  microk8s stop                # Stop MicroK8s"
echo "  microk8s reset               # Reset MicroK8s to default state"
echo ""
echo "📦 Available addons to enable:"
echo "  microk8s enable dashboard    # Kubernetes dashboard"
echo "  microk8s enable ingress      # Ingress controller"
echo "  microk8s enable registry     # Private container registry"
echo "  microk8s enable metrics-server # Metrics server"
echo ""
echo "🎯 To activate kubectl without sudo, run:"
echo "  newgrp microk8s"
echo ""
echo "Then verify and deploy:"
echo "  kubectl get nodes"
echo "  ./deploy.sh"
echo ""
