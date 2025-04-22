#!/bin/bash

# Update Cilium to enable Hubble
kubectl patch configmap cilium-config -n kube-system --type merge --patch "$(cat cilium-active-tracking-config.yaml | grep -A 100 data: | sed 's/data://')"

# Restart Cilium with new configuration
kubectl rollout restart deployment/cilium -n kube-system

# Wait for Cilium to be ready
kubectl rollout status deployment/cilium -n kube-system

# Enable Hubble in Cilium
cilium hubble enable

# Enable Hubble UI
cilium hubble enable --ui

# Verify Hubble is running
cilium status | grep Hubble

# Port forward Hubble UI
echo "Starting port forwarding for Hubble UI. Access the UI at http://localhost:12000"
kubectl port-forward -n kube-system svc/hubble-ui 12000:80 