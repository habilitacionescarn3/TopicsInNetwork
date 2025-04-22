# Monitoring Least Connection Load Balancing with Hubble UI

## Overview
Hubble UI provides a visual way to observe how traffic is distributed among backend pods using the least connection algorithm.

## Accessing Hubble UI
1. Access the Hubble UI at http://localhost:12000 after running the port-forwarding script.
2. The dashboard will show a service map of your cluster.

## Checking Connection Distribution

### 1. View Service Map
- Look for your `least-conn-service` in the service map
- Notice how it connects to the backend pods (the `web-app` instances)

### 2. Check Flow Statistics
- Click on the line connecting the client to the service
- The right panel will show flow statistics
- Observe that requests are distributed among backends

### 3. Use Service View
- Click on "Service Map" in the left sidebar
- Find and select `least-conn-service`
- The diagram will show all backends of this service
- The thickness of lines indicates traffic volume

### 4. Check Connection Count with Metrics View
- Click on "Metrics" in the left sidebar
- Select "HTTP" category
- Choose "HTTP Requests by Service" metric
- Filter by your service name
- This shows how requests are distributed across backends

### 5. Use Filters to Analyze Traffic Patterns
- In the top of the UI, click on the filter icon
- Filter flows by:
  - Source/destination namespace
  - Service name: `least-conn-service`
  - Protocol: TCP
- This isolates the traffic related to your least connection service

### 6. Observe Backend Distribution
In the Service View, you should observe that:
- Initial connections go to pods with zero connections
- As connections accumulate on some pods, new connections are sent to less loaded pods
- When connections close, those backends will start receiving new connections again

### 7. Verify Proper Load Balancing
The proper function of least connection algorithm can be verified by:
- Even distribution of traffic after sustained load
- New connections going to backends with fewer active connections
- Rebalancing of connections as existing ones terminate

## Troubleshooting

If you don't see proper least connection behavior in Hubble UI, check:

1. Verify active connection tracking is enabled:
```
kubectl exec -n kube-system cilium-xxxx -- cilium status | grep Active
```

2. Check connection tracking entries:
```
kubectl exec -n kube-system cilium-xxxx -- cilium bpf ct list global
```

3. Verify service is using least-conn algorithm:
```
kubectl exec -n kube-system cilium-xxxx -- cilium service list | grep least-conn
```

4. Check if debug messages show least-conn selection:
```
kubectl exec -n kube-system cilium-xxxx -- cilium monitor --type debug
``` 