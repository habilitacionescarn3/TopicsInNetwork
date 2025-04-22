.. only:: not (epub or latex or html)

    WARNING: You are looking at unreleased Cilium documentation.
    Please use the official rendered version released here:
    https://docs.cilium.io

.. _kubeproxy-free:

*****************************
Kubernetes Without kube-proxy
*****************************

This guide explains how to provision a Kubernetes cluster without ``kube-proxy``,
and to use Cilium to fully replace it. For simplicity, we will use ``kubeadm`` to
bootstrap the cluster.

For help with installing ``kubeadm`` and for more provisioning options please refer to
`the official Kubeadm documentation <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/>`_.

.. note::

   Cilium's kube-proxy replacement depends on the socket-LB feature,
   which requires a v4.19.57, v5.1.16, v5.2.0 or more recent Linux kernel.
   Linux kernels v5.3 and v5.8 add additional features that Cilium can use to
   further optimize the kube-proxy replacement implementation.

   Note that v5.0.y kernels do not have the fix required to run the kube-proxy
   replacement since at this point in time the v5.0.y stable kernel is end-of-life
   (EOL) and not maintained anymore on kernel.org. For individual distribution
   maintained kernels, the situation could differ. Therefore, please check with
   your distribution.

Quick-Start
###########

Initialize the control-plane node via ``kubeadm init`` and skip the
installation of the ``kube-proxy`` add-on:

.. note::
    Depending on what CRI implementation you are using, you may need to use the
    ``--cri-socket`` flag with your ``kubeadm init ...`` command.
    For example: if you're using Docker CRI you would use
    ``--cri-socket unix:///var/run/cri-dockerd.sock``.

.. code-block:: shell-session

    $ kubeadm init --skip-phases=addon/kube-proxy

Afterwards, join worker nodes by specifying the control-plane node IP address and
the token returned by ``kubeadm init``
(for this tutorial, you will want to add at least one worker node to the cluster):

.. code-block:: shell-session

    $ kubeadm join <..>

.. note::

    Please ensure that
    `kubelet <https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/>`_'s
    ``--node-ip`` is set correctly on each worker if you have multiple interfaces.
    Cilium's kube-proxy replacement may not work correctly otherwise.
    You can validate this by running ``kubectl get nodes -o wide`` to see whether
    each node has an ``InternalIP`` which is assigned to a device with the same
    name on each node.

For existing installations with ``kube-proxy`` running as a DaemonSet, remove it
by using the following commands below.

.. warning::
   Be aware that removing ``kube-proxy`` will break existing service connections. It will also stop service related traffic
   until the Cilium replacement has been installed.

.. code-block:: shell-session

   $ kubectl -n kube-system delete ds kube-proxy
   $ # Delete the configmap as well to avoid kube-proxy being reinstalled during a Kubeadm upgrade (works only for K8s 1.19 and newer)
   $ kubectl -n kube-system delete cm kube-proxy
   $ # Run on each node with root permissions:
   $ iptables-save | grep -v KUBE | iptables-restore

.. include:: ../../installation/k8s-install-download-release.rst

Next, generate the required YAML files and deploy them.

.. important::

   Make sure you correctly set your ``API_SERVER_IP`` and ``API_SERVER_PORT``
   below with the control-plane node IP address and the kube-apiserver port
   number reported by ``kubeadm init`` (Kubeadm will use port ``6443`` by default).

Specifying this is necessary as ``kubeadm init`` is run explicitly without setting
up kube-proxy and as a consequence, although it exports ``KUBERNETES_SERVICE_HOST``
and ``KUBERNETES_SERVICE_PORT`` with a ClusterIP of the kube-apiserver service
to the environment, there is no kube-proxy in our setup provisioning that service.
Therefore, the Cilium agent needs to be made aware of this information with the following configuration:

.. parsed-literal::

    API_SERVER_IP=<your_api_server_ip>
    # Kubeadm default is 6443
    API_SERVER_PORT=<your_api_server_port>
    helm install cilium |CHART_RELEASE| \\
        --namespace kube-system \\
        --set kubeProxyReplacement=true \\
        --set k8sServiceHost=${API_SERVER_IP} \\
        --set k8sServicePort=${API_SERVER_PORT}

.. note::

    Cilium will automatically mount cgroup v2 filesystem required to attach BPF
    cgroup programs by default at the path ``/run/cilium/cgroupv2``. To do that,
    it needs to mount the host ``/proc`` inside an init container
    launched by the DaemonSet temporarily. If you need to disable the auto-mount,
    specify ``--set cgroup.autoMount.enabled=false``, and set the host mount point
    where cgroup v2 filesystem is already mounted by using ``--set cgroup.hostRoot``.
    For example, if not already mounted, you can mount cgroup v2 filesystem by
    running the below command on the host, and specify ``--set cgroup.hostRoot=/sys/fs/cgroup``.

    .. code:: shell-session

        mount -t cgroup2 none /sys/fs/cgroup

This will install Cilium as a CNI plugin with the eBPF kube-proxy replacement to
implement handling of Kubernetes services of type ClusterIP, NodePort, LoadBalancer
and services with externalIPs. As well, the eBPF kube-proxy replacement also
supports hostPort for containers such that using portmap is not necessary anymore.

Finally, as a last step, verify that Cilium has come up correctly on all nodes and
is ready to operate:

.. code-block:: shell-session

    $ kubectl -n kube-system get pods -l k8s-app=cilium
    NAME                READY     STATUS    RESTARTS   AGE
    cilium-fmh8d        1/1       Running   0          10m
    cilium-mkcmb        1/1       Running   0          10m

Note, in above Helm configuration, the ``kubeProxyReplacement`` has been set to
``true`` mode. This means that the Cilium agent will bail out in case the
underlying Linux kernel support is missing.

By default, Helm sets ``kubeProxyReplacement=false``, which only enables
per-packet in-cluster load-balancing of ClusterIP services.

Cilium's eBPF kube-proxy replacement is supported in direct routing as well as in
tunneling mode.

Validate the Setup
##################

After deploying Cilium with above Quick-Start guide, we can first validate that
the Cilium agent is running in the desired mode:

.. code-block:: shell-session

    $ kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep KubeProxyReplacement
    KubeProxyReplacement:   True	[eth0 (Direct Routing), eth1]

Use ``--verbose`` for full details:

.. code-block:: shell-session

    $ kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
    [...]
    KubeProxyReplacement Details:
      Status:                True
      Socket LB:             Enabled
      Protocols:             TCP, UDP
      Devices:               eth0 (Direct Routing), eth1
      Mode:                  SNAT
      Backend Selection:     Random
      Session Affinity:      Enabled
      Graceful Termination:  Enabled
      NAT46/64 Support:      Enabled
      XDP Acceleration:      Disabled
      Services:
      - ClusterIP:      Enabled
      - NodePort:       Enabled (Range: 30000-32767)
      - LoadBalancer:   Enabled
      - externalIPs:    Enabled
      - HostPort:       Enabled
    [...]

As an optional next step, we will create an Nginx Deployment. Then we'll create a new NodePort service and
validate that Cilium installed the service correctly.

The following YAML is used for the backend pods:

.. code-block:: yaml

    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: my-nginx
    spec:
      selector:
        matchLabels:
          run: my-nginx
      replicas: 2
      template:
        metadata:
          labels:
            run: my-nginx
        spec:
          containers:
          - name: my-nginx
            image: nginx
            ports:
            - containerPort: 80

Verify that the Nginx pods are up and running:

.. code-block:: shell-session

    $ kubectl get pods -l run=my-nginx -o wide
    NAME                        READY   STATUS    RESTARTS   AGE   IP             NODE   NOMINATED NODE   READINESS GATES
    my-nginx-756fb87568-gmp8c   1/1     Running   0          62m   10.217.0.149   apoc   <none>           <none>
    my-nginx-756fb87568-n5scv   1/1     Running   0          62m   10.217.0.107   apoc   <none>           <none>

In the next step, we create a NodePort service for the two instances:

.. code-block:: shell-session

    $ kubectl expose deployment my-nginx --type=NodePort --port=80
    service/my-nginx exposed

Verify that the NodePort service has been created:

.. code-block:: shell-session

    $ kubectl get svc my-nginx
    NAME       TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
    my-nginx   NodePort   10.104.239.135   <none>        80:31940/TCP   24m

With the help of the ``cilium-dbg service list`` command, we can validate that
Cilium's eBPF kube-proxy replacement created the new NodePort service.
In this example, services with port ``31940`` were created (one for each of devices ``eth0`` and ``eth1``):

.. code-block:: shell-session

    $ kubectl -n kube-system exec ds/cilium -- cilium-dbg service list
    ID   Frontend               Service Type   Backend
    [...]
    4    10.104.239.135:80/TCP      ClusterIP      1 => 10.217.0.107:80/TCP
                                                   2 => 10.217.0.149:80/TCP
    5    0.0.0.0:31940/TCP          NodePort       1 => 10.217.0.107:80/TCP
                                                   2 => 10.217.0.149:80/TCP
    6    192.168.178.29:31940/TCP   NodePort       1 => 10.217.0.107:80/TCP
                                                   2 => 10.217.0.149:80/TCP
    7    172.16.0.29:31940/TCP      NodePort       1 => 10.217.0.107:80/TCP
                                                   2 => 10.217.0.149:80/TCP

Create a variable with the node port for testing:

.. code-block:: shell-session

    $ node_port=$(kubectl get svc my-nginx -o=jsonpath='{@.spec.ports[0].nodePort}')

At the same time we can verify, using ``iptables`` in the host namespace,
that no ``iptables`` rule for the service is present:

.. code-block:: shell-session

    $ iptables-save | grep KUBE-SVC
    [ empty line ]

Last but not least, a simple ``curl`` test shows connectivity for the exposed
NodePort as well as for the ClusterIP:

.. code-block:: shell-session

    $ curl 127.0.0.1:$node_port
    <!DOCTYPE html>
    <html>
    <head>
    <title>Welcome to nginx!</title>
    [....]

.. code-block:: shell-session

    $ curl 192.168.178.29:$node_port
    <!doctype html>
    <html>
    <head>
    <title>welcome to nginx!</title>
    [....]

.. code-block:: shell-session

    $ curl 172.16.0.29:$node_port
    <!doctype html>
    <html>
    <head>
    <title>welcome to nginx!</title>
    [....]

.. code-block:: shell-session

    $ curl 10.104.239.135:80
    <!DOCTYPE html>
    <html>
    <head>
    <title>Welcome to nginx!</title>
    [....]

As can be seen, Cilium's eBPF kube-proxy replacement is set up correctly.

Advanced Configuration
######################

This section covers a few advanced configuration modes for the kube-proxy replacement
that go beyond the above Quick-Start guide and are entirely optional.

Client Source IP Preservation
*****************************

Cilium's eBPF kube-proxy replacement implements various options to avoid
performing SNAT on NodePort requests where the client source IP address would otherwise
be lost on its path to the service endpoint.

- ``externalTrafficPolicy=Local``: The ``Local`` policy is generally supported through
  the eBPF implementation. In-cluster connectivity for services with ``externalTrafficPolicy=Local``
  is possible and can also be reached from nodes which have no local backends, meaning,
  given SNAT does not need to be performed, all service endpoints are available for
  load balancing from in-cluster side.

- ``externalTrafficPolicy=Cluster``: For the ``Cluster`` policy which is the default
  upon service creation, multiple options exist for achieving client source IP preservation
  for external traffic, that is, operating the kube-proxy replacement in :ref:`DSR<DSR Mode>`
  or :ref:`Hybrid<Hybrid Mode>` mode if only TCP-based services are exposed to the outside
  world for the latter.

Internal Traffic Policy
***********************

Similar to ``externalTrafficPolicy`` described above, Cilium's eBPF kube-proxy replacement
supports ``internalTrafficPolicy``, which translates the above semantics to in-cluster traffic.

- For services with ``internalTrafficPolicy=Local``, traffic originated from pods in the
  current cluster is routed only to endpoints within the same node the traffic originated from.

- ``internalTrafficPolicy=Cluster`` is the default, and it doesn't restrict the endpoints that
  can handle internal (in-cluster) traffic.

The following table gives an idea of what backends are used to serve connections to a service,
depending on the external and internal traffic policies:

+---------------------+-------------------------------------------------+
| Traffic policy      | Service backends used                           |
+----------+----------+-------------------------+-----------------------+
| Internal | External | for North-South traffic | for East-West traffic |
+==========+==========+=========================+=======================+
| Cluster  | Cluster  | All (default)           | All (default)         |
+----------+----------+-------------------------+-----------------------+
| Cluster  | Local    | Node-local only         | All (default)         |
+----------+----------+-------------------------+-----------------------+
| Local    | Cluster  | All (default)           | Node-local only       |
+----------+----------+-------------------------+-----------------------+
| Local    | Local    | Node-local only         | Node-local only       |
+----------+----------+-------------------------+-----------------------+

Selective Service Type Exposure
*******************************

By default, for a ``LoadBalancer`` service Cilium exposes corresponding
``NodePort`` and ``ClusterIP`` services. Likewise, for a new ``NodePort``
service, Cilium exposes the corresponding ``ClusterIP`` service.

If this behavior is not desired, then the ``service.cilium.io/type``
annotation can be used to pin the service creation only to a specific
service type:

.. code-block:: yaml

  apiVersion: v1
  kind: Service
  metadata:
    name: example-service
    annotations:
      service.cilium.io/type: LoadBalancer
  spec:
    ports:
      - port: 80
        targetPort: 80
    type: LoadBalancer
    allocateLoadBalancerNodePorts: false

In the above example only the ``LoadBalancer`` service is created without
corresponding ``NodePort`` and ``ClusterIP`` services. If the annotation
would be set to e.g. ``service.cilium.io/type: NodePort``, then only the
``NodePort`` service would be installed.

Host Proxy Delegation
*********************

If the selected service backend IP for a given service matches the local
node IP, the annotation ``service.cilium.io/proxy-delegation: delegate-if-local``
will pass the received packet unmodified to the upper stack, so that a
L7 proxy such as Envoy (if present) can handle the request in the host
namespace.

If the selected service backend is a remote IP, then the received packet
is not pushed to the upper stack and instead the BPF code forwards the
packet natively with the configured forwarding method to the remote IP.

.. code-block:: yaml

  apiVersion: v1
  kind: Service
  metadata:
    name: example-service
    annotations:
      service.cilium.io/proxy-delegation: delegate-if-local
  spec:
    ports:
      - port: 80
        targetPort: 80
    type: LoadBalancer

In combination with ``externalTrafficPolicy=Local`` this mechanism also allows
for pushing all traffic to the upper proxy.

Non-presence of the ``service.cilium.io/proxy-delegation`` annotation leaves
all forwarding to BPF natively which is also the default for the kube-proxy
replacement case.

Selective Service Node Exposure
*******************************

By default, Cilium exposes Kubernetes services on all nodes in the cluster. To expose a
service only on a subset of the nodes instead, use the ``service.cilium.io/node`` label for
the relevant nodes. For example, label a node as follows:

.. code-block:: shell-session

  $ kubectl label node node_name service.cilium.io/node=beefy

To add a new service that should only be exposed to nodes with label ``service.cilium.io/node=beefy``, install the service as follows:

.. code-block:: yaml

  apiVersion: v1
  kind: Service
  metadata:
    name: example-service
    annotations:
      service.cilium.io/node: beefy
  spec:
    selector:
      app: example
    ports:
      - port: 8765
        targetPort: 9376
    type: LoadBalancer

It's also possible to control the service node exposure via the annotation ``service.cilium.io/node-selector`` - where
the annotation value contains the label selector. This way, the service is only exposed on nodes that match the
node label selector. The annotation ``service.cilium.io/node-selector`` always has priority over 
``service.cilium.io/node`` if both exist on the same service.

.. code-block:: yaml

  apiVersion: v1
  kind: Service
  metadata:
    name: example-service
    annotations:
      service.cilium.io/node-selector: "service.cilium.io/node in ( beefy , slow )"
  spec:
    selector:
      app: example
    ports:
      - port: 8765
        targetPort: 9376
    type: LoadBalancer

Note that changing a node label after a service has been exposed matching that label does not
automatically update the list of nodes where the service is exposed. To update exposure of the
service after changing node labels, restart the Cilium agent. Generally it is advised to fixate the
node label upon joining the Kubernetes cluster and retain it throughout the node's lifetime.

.. _maglev:

Maglev Consistent Hashing
*************************

Cilium's eBPF kube-proxy replacement supports consistent hashing by implementing a variant
of `The Maglev hashing <https://static.googleusercontent.com/media/research.google.com/ko//pubs/archive/44824.pdf>`_
in its load balancer for backend selection. This improves resiliency in case of
failures. As well, it provides better load balancing properties since Nodes added to the cluster will
make consistent backend selection throughout the cluster for a given 5-tuple without
having to synchronize state with the other Nodes. Similarly, upon backend removal the backend
lookup tables are reprogrammed with minimal disruption for unrelated backends (at most 1%
difference in the reassignments) for the given service.

Maglev hashing for services load balancing can be enabled by setting ``loadBalancer.algorithm=maglev``:

.. parsed-literal::

    helm install cilium |CHART_RELEASE| \\
        --namespace kube-system \\
        --set kubeProxyReplacement=true \\
        --set loadBalancer.algorithm=maglev \\
        --set k8sServiceHost=${API_SERVER_IP} \\
        --set k8sServicePort=${API_SERVER_PORT}

Note that Maglev hashing is applied only to external (N-S) traffic. For
in-cluster service connections (E-W), sockets are assigned to service backends
directly, e.g. at TCP connect time, without any intermediate hop and thus are
not subject to Maglev. Maglev hashing is also supported for Cilium's
:ref:`XDP<XDP Acceleration>` acceleration.

There are two more Maglev-specific configuration settings: ``maglev.tableSize``
and ``maglev.hashSeed``.

``maglev.tableSize`` specifies the size of the Maglev lookup table for each single service.
`Maglev <https://static.googleusercontent.com/media/research.google.com/ko//pubs/archive/44824.pdf>`__
recommends the table size (``M``) to be significantly larger than the number of maximum expected
backends (``N``). In practice that means that ``M`` should be larger than ``100 * N`` in
order to guarantee the property of at most 1% difference in the reassignments on backend
changes. ``M`` must be a prime number. Cilium uses a default size of ``16381`` for ``M``.
The following sizes for ``M`` are supported as ``maglev.tableSize`` Helm option:

+----------------------------+
| ``maglev.tableSize`` value |
+============================+
| 251                        |
+----------------------------+
| 509                        |
+----------------------------+
| 1021                       |
+----------------------------+
| 2039                       |
+----------------------------+
| 4093                       |
+----------------------------+
| 8191                       |
+----------------------------+
| 16381                      |
+----------------------------+
| 32749                      |
+----------------------------+
| 65521                      |
+----------------------------+
| 131071                     |
+----------------------------+

For example, a ``maglev.tableSize`` of ``16381`` is suitable for a maximum of ``~160`` backends
per service. If a higher number of backends are provisioned under this setting, then the
difference in reassignments on backend changes will increase. Note that changing the table
size (``M``) triggers a recalculation of the lookup table and can temporarily lead to inconsistent
backend selection for new traffic until all nodes have converged and completed their agent restart.

The ``maglev.hashSeed`` option is recommended to be set in order for Cilium to not rely on the
fixed built-in seed. The seed is a base64-encoded 12 byte-random number, and can be
generated once through ``head -c12 /dev/urandom | base64 -w0``, for example.
Every Cilium agent in the cluster must use the same hash seed for Maglev to work.

The below deployment example is generating and passing such seed to Helm as well as setting the
Maglev table size to ``65521`` to allow for ``~650`` maximum backends for a
given service (with the property of at most 1% difference on backend reassignments):

.. parsed-literal::

    SEED=$(head -c12 /dev/urandom | base64 -w0)
    helm install cilium |CHART_RELEASE| \\
        --namespace kube-system \\
        --set kubeProxyReplacement=true \\
        --set loadBalancer.algorithm=maglev \\
        --set maglev.tableSize=65521 \\
        --set maglev.hashSeed=$SEED \\
        --set k8sServiceHost=${API_SERVER_IP} \\
        --set k8sServicePort=${API_SERVER_PORT}


Note that enabling Maglev will have a higher memory consumption on each Cilium-managed Node compared
to the default of ``loadBalancer.algorithm=random`` given ``random`` does not need the extra lookup
tables. However, ``random`` won't have consistent backend selection.

.. _DSR mode:

Direct Server Return (DSR)
**************************

By default, Cilium's eBPF NodePort implementation operates in SNAT mode. That is,
when node-external traffic arrives and the node determines that the backend for
the LoadBalancer, NodePort, or services with externalIPs is at a remote node, then the
node is redirecting the request to the remote backend on its behalf by performing
SNAT. This does not require any additional MTU changes. The cost is that replies
from the backend need to make the extra hop back to that node to perform the
reverse SNAT translation there before returning the packet directly to the external
client.

This setting can be changed through the ``loadBalancer.mode`` Helm option to
``dsr`` in order to let Cilium's eBPF NodePort implementation operate in DSR mode.
In this mode, the backends reply directly to the external client without taking
the extra hop, meaning, backends reply by using the service IP/port as a source.

Another advantage in DSR mode is that the client's source IP is preserved, so policy
can match on it at the backend node. In the SNAT mode this is not possible.
Given a specific backend can be used by multiple services, the backends need to be
made aware of the service IP/port which they need to reply with. Cilium encodes this
information into the packet (using one of the dispatch mechanisms described below),
at the cost of advertising a lower MTU. For TCP services, Cilium
only encodes the service IP/port for the SYN packet, but not subsequent ones. This
optimization also allows to operate Cilium in a hybrid mode as detailed in the later
subsection where DSR is used for TCP and SNAT for UDP in order to avoid an otherwise
needed MTU reduction.

In some public cloud provider environments that implement source /
destination IP address checking (e.g. AWS), the checking has to be disabled in
order for the DSR mode to work.

By default Cilium uses special ExternalIP mitigation for CVE-2020-8554 MITM vulnerability.
This may affect connectivity targeted to ExternalIP on the same cluster.
This mitigation can be disabled by setting ``bpf.disableExternalIPMitigation`` to ``true``.

.. _DSR mode with Option:

Direct Server Return (DSR) with IPv4 option / IPv6 extension Header
*******************************************************************

In this DSR dispatch mode, the service IP/port information is transported to the
backend through a Cilium-specific IPv4 Option or IPv6 Destination Option extension header.
It requires Cilium to be deployed in :ref:`arch_direct_routing`, i.e.
it will not work in :ref:`arch_overlay` mode.

This DSR mode might not work in some public cloud provider environments
due to the Cilium-specific IP options that could be dropped by an underlying network fabric.
In case of connectivity issues to services where backends are located on
a remote node from the node that is processing the given NodePort request,
first check whether the NodePort request actually arrived on the node
containing the backend. If this was not the case, then consider either switching to
DSR with Geneve (as described below), or switching back to the default SNAT mode.

The above Helm example configuration in a kube-proxy-free environment with DSR-only mode
enabled would look as follows:

.. parsed-literal::

    helm install cilium |CHART_RELEASE| \\
        --namespace kube-system \\
        --set routingMode=native \\
        --set kubeProxyReplacement=true \\
        --set loadBalancer.mode=dsr \\
        --set loadBalancer.dsrDispatch=opt \\
        --set k8sServiceHost=${API_SERVER_IP} \\
        --set k8sServicePort=${API_SERVER_PORT}

.. _DSR mode with Geneve:

Direct Server Return (DSR) with Geneve
**************************************
By default, Cilium with DSR mode encodes the service IP/port in a Cilium-specific
IPv4 option or IPv6 Destination Option extension so that the backends are aware of
the service IP/port, which they need to reply with.

However, some data center routers pass packets with unknown IP options to software
processing called "Layer 2 slow path". Those routers drop the packets if the amount
of packets with IP options exceeds a given threshold, which may significantly affect
network performance.

Cilium offers another dispatch mode, DSR with Geneve, to avoid this problem.
In DSR with Geneve, Cilium encapsulates packets to the Loadbalancer with the Geneve
header that includes the service IP/port in the Geneve option and redirects them
to the backends.

The Helm example configuration in a kube-proxy-free environment with DSR and
Geneve dispatch enabled would look as follows:

.. parsed-literal::
    helm install cilium |CHART_RELEASE| \\
        --namespace kube-system \\
        --set routingMode=native \\
        --set tunnelProtocol=geneve \\
        --set kubeProxyReplacement=true \\
        --set loadBalancer.mode=dsr \\
        --set loadBalancer.dsrDispatch=geneve \\
        --set k8sServiceHost=${API_SERVER_IP} \\
        --set k8sServicePort=${API_SERVER_PORT}

DSR with Geneve is compatible with the Geneve encapsulation mode (:ref:`arch_overlay`).
It works with either the direct routing mode or the Geneve tunneling mode. Unfortunately,
it doesn't work with the vxlan encapsulation mode.

The example configuration in DSR with Geneve dispatch and tunneling mode is as follows.

.. parsed-literal::
    helm install cilium |CHART_RELEASE| \\
        --namespace kube-system \\
        --set routingMode=tunnel \\
        --set tunnelProtocol=geneve \\
        --set kubeProxyReplacement=true \\
        --set loadBalancer.mode=dsr \\
        --set loadBalancer.dsrDispatch=geneve \\
        --set k8sServiceHost=${API_SERVER_IP} \\
        --set k8sServicePort=${API_SERVER_PORT}

.. _Hybrid mode:

Hybrid DSR and SNAT Mode
************************

Cilium also supports a hybrid DSR and SNAT mode, that is, DSR is performed for TCP
and SNAT for UDP connections.

This removes the need for manual MTU changes in the network while still benefiting
from the latency improvements through the removed extra hop for replies, in particular,
when TCP is the main transport for workloads.

The mode setting ``loadBalancer.mode`` allows to control the behavior through the
options ``dsr``, ``snat``, ``annotation``, and ``hybrid``. By default the ``snat``
mode is used in the agent.

A Helm example configuration in a kube-proxy-free environment with DSR enabled in
hybrid mode would look as follows:

.. parsed-literal::

    helm install cilium |CHART_RELEASE| \\
        --namespace kube-system \\
        --set routingMode=native \\
        --set kubeProxyReplacement=true \\
        --set loadBalancer.mode=hybrid \\
        --set k8sServiceHost=${API_SERVER_IP} \\
        --set k8sServicePort=${API_SERVER_PORT}

Annotation-based DSR and SNAT Mode
**********************************

Cilium also supports an annotation-based DSR and SNAT mode, that is, services
can be exposed by default via SNAT and on-demand as DSR (or vice versa):

.. code-block:: yaml

  apiVersion: v1
  kind: Service
  metadata:
    name: example-service
    annotations:
      service.cilium.io/type: LoadBalancer
      service.cilium.io/forwarding-mode: dsr
  spec:
    ports:
      - port: 80
        targetPort: 80
    type: LoadBalancer

Note that the ``forwarding-mode`` annotation must be set at service creation time
and should not be changed during the lifetime of that service. Changing the value
of the annotation or removing the annotation while the service is installed breaks
connections.

The above example installs the Kubernetes service only as type ``LoadBalancer``,
that is, without the corresponding ``NodePort`` and ``ClusterIP`` services, and
uses the configured DSR method to forward the packets instead of default SNAT.
The Helm setting ``loadBalancer.mode=snat`` defines the default as SNAT in this
example. A ``loadBalancer.mode=dsr`` would have switched the default to DSR instead
and then ``service.cilium.io/forwarding-mode: snat`` annotation can be used to
switch to SNAT instead.

A Helm example configuration in a kube-proxy-free environment with DSR enabled in
annotation mode with SNAT default would look as follows:

.. parsed-literal::

    helm install cilium |CHART_RELEASE| \\
        --namespace kube-system \\
        --set routingMode=native \\
        --set kubeProxyReplacement=true \\
        --set loadBalancer.mode=snat \\
        --set bpf.lbModeAnnotation=true \\
        --set k8sServiceHost=${API_SERVER_IP} \\
        --set k8sServicePort=${API_SERVER_PORT}

Annotation-based Load Balancing Algorithm Selection
***************************************************

Cilium has the ability to specify the load balancing algorithm on a per-service
basis through the ``service.cilium.io/lb-algorithm`` annotation. Setting
``bpf.lbAlgorithmAnnotation=true`` opts into this ability for the BPF and
corresponding agent code. A typical use-case is to reduce the memory footprint
which comes with Maglev given the latter requires large lookup tables for each
service. Thus, if not all services need consistent hashing, then these can
fallback to a random selection instead.

By default, if no service annotation is provided, the logic falls back to use
whichever method was specified globally through ``loadBalancer.algorithm``. The
latter supports either ``random``, ``maglev``, or ``least-conn`` as values today with ``random``
being the default if ``loadBalancer.algorithm`` was not explicitly set via Helm.
