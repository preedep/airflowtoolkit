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

# Check if microk8s is already installed
if command -v microk8s &> /dev/null; then
    echo "⚠️  MicroK8s is already installed."
    microk8s version
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo "Removing existing MicroK8s installation..."
    sudo snap remove microk8s
fi

echo "Step 1: Installing MicroK8s via snap..."
sudo snap install microk8s --classic --channel=1.28/stable

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
sudo microk8s enable storage
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
kubectl version --client --short 2>/dev/null || kubectl version --client
echo ""
echo "helm version:"
helm version --short 2>/dev/null || helm version

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "⚠️  IMPORTANT: You need to log out and log back in for group changes to take effect!"
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
echo "🎯 Next steps:"
echo "  1. Log out and log back in (or run: newgrp microk8s)"
echo "  2. Verify: kubectl get nodes"
echo "  3. Deploy Airflow: ./deploy.sh"
echo ""
