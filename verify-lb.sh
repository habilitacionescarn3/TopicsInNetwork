#!/bin/bash

# Check Cilium status and configuration
echo "Checking Cilium configuration..."
cilium status
echo
echo "Checking Cilium service list..."
cilium service list
echo
echo "Checking connection tracking status..."
cilium bpf ct list global
echo

# Get service IP
SERVICE_IP=$(kubectl get svc example-lb-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$SERVICE_IP" ]; then
    echo "Waiting for LoadBalancer IP..."
    exit 1
fi

# Test load balancing distribution
echo "Testing load distribution across backends..."
for i in {1..100}; do
    curl -s http://$SERVICE_IP/
    echo "Request $i completed"
    sleep 0.1
done

# Show connection statistics
echo
echo "Connection tracking statistics:"
cilium bpf ct list global | grep -v RELATED | awk '{print $4}' | sort | uniq -c

# Show service backend statistics
echo
echo "Service backend statistics:"
cilium service list | grep example-lb-service -A 3 