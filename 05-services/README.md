# Services

In this chapter we will investigate the concept of services and different service types. In the Pod chapter we already learned that Pods do not receive a stable IP address. However, we want to be able to access our services both internally and externally of the cluster based at a stable entrypoint. For that exact reason, K8s introduces the concept of a `Service`:

Services act as a central entrypoint for e.g. a backend which is backed by one or more Pods. The creation of a service automatically results in a DNS name being generated based on the service name, which can be read by all entities in the cluster. This way, services can be discovered ("service discovery"): we dont have to juggle IP addresses, routes etc., we only need the name of a service. A similar concept can be found in Docker Compose: containers can be addressed via their service name rather than their IP address.

Kubernetes provides multiple service types with different use-cases: `ClusterIP`, `NodePort`, and `LoadBalancer`. They differ in how a service is exposed and if it is externally reachable. We will take a look at the different service types in that exact order, as they each build on the previous type.

## ClusterIP

The simplest service type which is also the default if not otherweise specified is the type `ClusterIP`. This service type assignes a service a cluster-internal IP address, which remains stable during the service's lifetime. The service is only reachable from within the cluster.

```bash
kubectl apply -f manifests/pod_nginx.yml
kubectl apply -f manifests/service_clusterip.yml
```

The manifest `pod_nginx.yml` creates two pods, `web-1` and `web-2`. A service identifies the Pods that back it through label selectors. Pods that are selected are also called endpoints. Currently, the service service only selects the Pod `web-1`, as the label `app: web` is missing on the Pod `web-2`.

We can view the service:

```bash
kubectl get services
```

<details>
<summary>Expected Output</summary>

```text
NAME   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
web    ClusterIP   172.16.119.218   <none>        80/TCP    2m14s
```
</details>

Here we see that the service received a cluster-internal IP address, which is within the subnet we set previously: `--service-cidr=172.16.64.0/18`. Additionally, we see that no external IP was assigned.

We can also send a request to the service using its cluster-internal DNS-Name:

```bash
kubectl apply -f manifests/pod_debug_netshoot.yml
kubectl exec -it netshoot -- bash
netshoot:~# curl web
```

<details>
<summary>Expected Output</summary>

```text
<h1>Hello from pod 1</h1>
```
</details>

The DNS-name `web` is sufficient in this case. Taking a look at the `/etc/resolv.conf` file in the Netshoot Pod answers the question why this is the case:

```bash
netshoot:~# cat /etc/resolv.conf 
```

<details>
<summary>Expected Output</summary>

```text
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 172.16.64.10
options ndots:5
```
</details>

Here we find the IP address we set for the cluster DNS-Server: `--cluster-dns=172.16.64.10`. We also find multiple search-domains being set. One for the namespace, one for services, and one for the cluster. Based on this, the following DNS-Names will resolve to the IP address of the `web` service as well:

- `web.default`
- `web.default.svc`
- `web.default.svc.cluster.local`

If we want to reach the service from another namespace, we must at least specify the namespace in the DNS name: `<name>.<namespace>`.

### View Service Endpoints

As mentioned above, a service identifies its backend Pods through selector labels. The selected Pods are called Endpoints. The service itself is just a fassade: the Pods themselves are what's answering the requests that are being sent to the service.

We already encountered the concept of Endpoints during the Readiness-Probe in the Pod chapter; but now we can contextualize them better: if a Pod is not ready to handle requests, i.e. its Readiness Probe fails, it is removed as an available Endpoint. For a service which uses this Pod as an Endpoint, this means that no incoming requests are sent to this Pod. If the Pod is the only Pod backing a service, the service itself is not reachable or useable.

We can view the Endpoints for the `web` service like this:

```bash
kubectl get endpoints web
```

<details>
<summary>Expected Output</summary>

```text
NAME   ENDPOINTS       AGE
web    172.16.0.19:80   10m
```

The deprecation-warning (`Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice`) can be ignored.
</details>

We can see one Endpoint, which corresponds to the Pod `web-1`. With:

```bash
kubectl get pods -o wide
```

we can see that the IP address of the Pod matches with the one listed in the Endpoints. Additional information about the service can be retrieved using the `describe` verb:

```bash
kubectl describe service web
```

<details>
<summary>Expected Output (Excerpt)</summary>

```text
Selector:          app=web
IP:                172.16.96.144
Port:               <unset>  80/TCP
TargetPort:         80/TCP
Endpoints:          172.16.0.8:80
```
</details>

If we remove one of the selector labels from the `web-1` Pod, we can also see that the Pod is not being treated as an Endpoint anymore:

```bash
kubectl label pod web-1 app- 
```

If we query the Endpoints of the service now:

```bash
kubectl get endpoints web
```

the IP address of the Pod is removed, the Service has no Endpoints anymore. If we now query the service, we dont get an answer anymore:

```bash
kubectl exec -it netshoot -- bash
netshoot:~# curl web
curl: (7) Failed to connect to web:80 after 2 ms: Could not connect to server
```

If we label the Pod again:

```bash
kubectl label pod web-1 app=web
```

The Endpoint is added and the service becomes reachable again.

### Service Load-Balancing

If a service has multiple Endpoints, it effectively works as a Layer 4 Load-Balancer. Currently, the service only has one Endpoint:

```bash
kubectl get endpoints web
```

In the resource manifest `pod_nginx.yml` there is a second Pod `web-2`, which should also be used for the `web` service. However, the Pod is currently missing the required labels to match the selector labels of the service. If we add these labels to the Pod:

```bash
kubectl label pod web-2 app=web
```

We can now see that the service has two Endpoints:

```bash
kubectl get endpoints web
```

If we now query the service multiple times using the netshoot container:

```bash
kubectl exec -it netshoot -- bash
netshoot:~# for i in $(seq 1 5); do curl -s web; done
```

we can see that we get responses from different Pods. Behind the scenes the requests are load-balanced on L4 with equal probabilities to all available endpoints.

<details>
<summary>Expected Output (Excerpt)</summary>

```text
<h1>Hello from pod 2</h1>
<h1>Hello from pod 1</h1>
<h1>Hello from pod 1</h1>
<h1>Hello from pod 2</h1>
<h1>Hello from pod 2</h1>
```
</details>

## NodePort

The service type `NodePort` exposes a service externally on all Cluster nodes on their own IP address on the same port. So if we have three K8s nodes with IPs `192.168.1.[10-12]`, and the service is externally reachable at port `xyz`, we can reach the service at `192.168.1.[10-12]:xyz`. This port can be set manually like in the manifest `service_nodeport.yml`. If not set, the port is chosen at random from the range `30000-32767`. However, when setting the port manually, we can still only choose from that range.

Internally, `NodePort` also creates a cluster-IP for the service, and NATs external requests to the service IP. However, even if we send all requests to only one of the K8s nodes, the underlying cluster-IP service will still load-balance requests to all available enpdoints. This can potentially include replicas on other K8s nodes. This inter-node traffic is handled by `kube-proxy`.

The service will be reachable internally using the automatically created DNS-Name which maps to the cluster-internal IP, and externally via the Node-IP and external port:

```bash
kubectl apply -f manifests/service_nodeport.yml
kubectl get service web-nodeport
```

<details>
<summary>Expected Output</summary>

```text
NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
web-nodeport   NodePort   172.16.81.54   <none>        80:30080/TCP   11s
```
</details>

From the output we can see that the specified port `30080` is used, and maps to the internal service port `80`. We can now send a request to one of the node IPs at this port to reach the service:

```bash
kubectl get nodes -o wide
# Internal-IP = Node-IP
curl http://<node-ip>:30080
```

<details>
<summary>Expected Output</summary>

```text
<h1>Hello from pod 2</h1>
```
</details>

Again, we can observe load-balancing behavior.

## LoadBalancer

The service type `LoadBalancer` maps an internal service and port to an external IP address and an external port. The benefit is that we can use well-known ports like `80` or `443`, while the `NodePort` type is constrained to ports in the 30k-range.

The naming of the service type is a bit confusing: all service types load-balance requests between multiple endpoints if available. The service type `LoadBalancer` can use an additional, external load-balancer. Compared to `NodePort`, this can have the benefit of e.g. automatic failover if one of the K8s nodes fails. So instead of sending requests to the node-IP directly, requests are sent to the external load-balancer IP, which then forwards the traffic to one of the reachable node IPs.

In managed K8s clusters, this external load-balancer is typically managed by the cloud provider, which maps e.g. a public IP address to the internal Endpoint. Since we are our own cloud provider, we have to manage this external load-balancer ourselves. For this, we will use MetalLB.

### Install MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
```

<details>
<summary>Expected Output (Excerpt)</summary>

```text
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io created
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io created
serviceaccount/controller created
serviceaccount/speaker created
deployment.apps/controller created
daemonset.apps/speaker created
```
</details>

Afterwards, wait until MetalLB has rolled out successfully:

```bash
kubectl rollout status deployment/controller -n metallb-system --timeout=60s
kubectl rollout status daemonset/speaker -n metallb-system --timeout=60s
```

<details>
<summary>Expected Output</summary>

```text
deployment "controller" successfully rolled out
daemon set "speaker" successfully rolled out
```
</details>

MetalLB uses ARP to manage Load-Balancer IP addresses: if a client in the same LAN sends an ARP request to resolve the load-balancer IP, MetalLB will answer with an ARP reply, which maps the virtual load-balancer IP address to the MAC-address of one of the K8s nodes interfaces. Afterwards, all traffic will be sent to that node. However, if this node fails, MetalLB will detect the failure, and announce a different MAC-address using a gratuitous ARP, i.e. "answering a question nobody asked". This updates the ARP caches of LAN clients, re-routing all traffic to the load-balancer IP to a different node, achieving automatic failover. However, this switch is not instant; thus "true" HA is not achieved using this system.

To configure MetalLB, two pieces are needed:

- MetalLB requires a pool from which it can pull IP addresses to act as load-balancer IPs. Each service with service type `LoadBalancer` will receive an IP address from this pool.
- The pool must be made available using a L2 advertisement, which is the ARP-mechanism discussed above.

**Important**: its important that the IP range in `metallb_ip_address_pool.yml` is within your LAN subnet and not using by other devices. Ensure to update the range in the manifest before applying!

The nessesary configuration can be managed using resource manifests:

```bash
kubectl apply -f manifests/metallb_ip_address_pool.yml
kubectl apply -f manifests/metallb_l2_advertisement.yml
```

### View external IP

After applying, we can now create a service with the type `LoadBalancer`:

```bash
kubectl apply -f manifests/service_loadbalancer.yml
kubectl get service web-lb
```

<details>
<summary>Expected Output</summary>

```text
NAME     TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
web-lb   LoadBalancer   172.16.113.138   10.24.1.20    80:30354/TCP   45s
```

**Hint**: if instead of an external IP the status is shown as `<pending>`, something went wrong with the MetalLB installation!
</details>

We can see that the service received an external IP address. The service is reachable on port `80`:

```bash
curl <10.24.1.20 / external IP>
```

We can also see a `NodePort` mapping of service port `80` to node-port `30354`. What's up with that? 

As mentioned previously, the service types build on each other: the `LoadBalancer` is responsible to pull in the traffic via the load-balancer IPs to the nodes. Once there, forwarding rules that build upon the `NodePort` plumbing, that is DNATing traffic to the service endpoints and forwarding using `kube-proxy`, are extended to also accept the load-balancer IP alongside the node IP as destination IP. So instead of copying the same machinery, `LoadBalancer` extends the already existing logic. That's why creating a `LoadBalancer` service implicitly also creates a `NodePort`, which itself builds upon and thus also creates a `ClusterIP`.

We can also verify this by sending a request to the node-port that was created for the `LoadBalancer`:

```bash
curl <Node IP>:30354
```

All of this behavior is implemented by `kube-proxy`, which manages the iptables on the K8s nodes. Some CNIs replace `kube-proxy` and implement the functionality on their own, e.g. using eBPF.

## Cleanup

```bash
bash cleanup.sh
```

Continue with [ConfigMaps & Secrets](06-configmaps-secrets.md).
