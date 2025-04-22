#!/bin/bash

# Deploy the service
kubectl apply -f least-conn-service.yaml

# Wait for the deployment to be ready
echo "Waiting for deployment to be ready..."
kubectl rollout status deployment/web-app

# Get the service IP
SERVICE_IP=$(kubectl get svc least-conn-service -o jsonpath='{.spec.clusterIP}')
echo "Service IP: $SERVICE_IP"

# Start Hubble UI in background
echo "Starting Hubble UI port forwarding in the background..."
kubectl port-forward -n kube-system svc/hubble-ui 12000:80 > /dev/null 2>&1 &
HUBBLE_PID=$!
echo "Hubble UI is available at http://localhost:12000"
echo "Please open this URL in your browser to monitor traffic"
echo "Press Enter to continue..."
read

# Generate traffic with varying delays to simulate different loads on backends
echo "Generating traffic to simulate different connection loads"
for i in {1..20}; do
    # Send 5 requests to backend 1
    for j in {1..5}; do
        curl -s http://$SERVICE_IP/ > /dev/null &
    done
    echo "Sent 5 requests - should be directed to least loaded backend"
    sleep 2
    
    # Send 3 requests to another backend
    for j in {1..3}; do
        curl -s http://$SERVICE_IP/ > /dev/null &
    done
    echo "Sent 3 more requests - should be distributed based on connection count"
    sleep 3
done

# Check connection tracking table
echo "Checking connection tracking table:"
kubectl exec -n kube-system $(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -n 1) -- cilium bpf ct list global

# Show service backends and their selection
echo "Checking Cilium service list:"
kubectl exec -n kube-system $(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -n 1) -- cilium service list | grep least-conn -A 10

# Kill background port forwarding
kill $HUBBLE_PID 