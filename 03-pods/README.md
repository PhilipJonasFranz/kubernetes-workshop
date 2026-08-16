# Pods

In Kubernetes, Pods are the smallest deployable unit. Compared to Docker, where individual containers are managed, a Pod can consist out of one or multiple containers, e.g. one or more main-containers, and one or more init-containers or sidecars. Other than that, the concept is similar: a container within a Pod runs an image, can have environment variables, configuration files and data volumes, and is doing the actual work.

Pods are considered ephermeral in Kubernetes: they are not permanent, but temporary entities. K8s can, if nessesary, delete or recreate them. This enables dynamic scaling: add additional replicas if the load increases, throw them away again if it decreases. For this to work, the state must be decoupled from the compute. We will take a closer look at this in the "Volumes" chapter.

Pods are assigned a unique, semi-stable IP address by K8s. This IP can be used to communicate with pods from anywhere in the cluster. However, when a Pod is recreated, its IP might change. So how do we know where to find a Pod and how to contact it? Typically: you dont! And in K8s this is typically not needed, as the access to Pods is abstracted through a Service, which we will investigate in a later chapter.

## Creating a Pod

Let's start with a simple example. The manifest `manifests/pod_nginx.yml` specifies a Pod with a single container. The field `spec` contains the description of the Pod, including a list of the contained containers. This is also where the nginx container is specified, including its name and container image. We use the `nginx:stable` image. We also specify port `80`, since this is the port where nginx will be listening, however; this is only informative, and does have not an effect of reachability or firewalling.

Let's create the Pod:

```bash
kubectl apply -f manifests/pod_nginx.yml
```

<details>
<summary>Expected Output</summary>

```text
pod/web created
```
</details>

## List Pods

The pod was created. You can view it with:

```bash
kubectl get pods
kubectl get pods -o wide
```

Initially, the status is shown as `ContainerCreating`. This means that the Pod was placed by the K8s Scheduler on a node, and the Container Runtime is busy creating the container. If the container image is not already present of the node, this means that the Container Runtime must pull the image to the node. As soon as the container was created, the status should change to `Running`.

With `-o wide` additional information, such as the IP address of the Pod is also printed. Notice that the IP of the Pod is contained in the `--cluster-cidr` subnet we specified during the cluster setup step.

<details>
<summary>Expected Output</summary>

```text
NAME   READY   STATUS    RESTARTS   AGE
web    1/1     Running   0          8s

NAME   READY   STATUS    RESTARTS   AGE   IP           NODE
web    1/1     Running   0          8s    172.16.0.5   k3s-...
```
</details>

## Details & Events of a Pod

We can also show the events that are associated with the Pod:

```bash
kubectl describe pod web
```

In the list of events, you should see K8s reporting that the scheduler selected a node where the pod should be run. Afterwards, the image for the nginx is pulled. Then the `nginx` container is created and started. Notice that the events specifically name a container, not a Pod!

In the `From` column you can also see the component that reported the Event, in this case its the `kubelet`. As stated in the introduction, the Kubelet is responsible to coordinate with the Container Runtime on the node and to report back to the control-plane, which is what we can see here.

All containers in a Pod share the same IP and Ports of the Pod they are running in, since a Pod is assigned only a single IP address. Under the hood, all containers of the Pod are run in the same network-namespace.

<details>
<summary>Expected Output (Excerpt)</summary>

```text
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  12s   default-scheduler  Successfully assigned default/web to k3s-...
  Normal  Pulling    13s   kubelet            Pulling image "nginx:stable"
  Normal  Pulled     8s    kubelet            Successfully pulled image "nginx:stable" in 4.9s
  Normal  Created    8s    kubelet            Container created
  Normal  Started    7s    kubelet            Container started
```
</details>

## View Container Logs

Similarily to Docker you can view the Logs of a Container running in a Pod:

```bash
kubectl logs web
kubectl logs -f web
```

<details>
<summary>Expected Output (Excerpt)</summary>

```text
/docker-entrypoint.sh: Configuration complete; ready for start up
.../07/21 ... [notice] 1#1: nginx/1.30.4
.../07/21 ... [notice] 1#1: start worker processes
```
</details>

## Running Commands in a Container

Also like in Docker, you can run commands in a container. This can also be used to open a shell in a container if the binary is present in the containers PATH:

```bash
kubectl exec -it web -- sh
```

## Port-Forwarding to a Pod

To temporarily access a process that is listening on a port in a Pod, you can start a port-forwarding to the local system.

When doing this, its important to consider where the port-forwarding is started. If you are using kubectl or Freelens on your local machine, the service will be port-forwarded to your machine's `localhost`. If youre connected to a node via SSH, the service will only be reachable on `localhost` on the node. To fix this, you can pass an additional argument:

For example, if we want to forward port `80` of the Pod `web` to port `8080` on the local host:

**Port-Forwarding running on local host**:

```bash
kubectl port-forward pod/web 8082:80
# Afterwards in browser / curl: http://localhost:8082
```

**Port-Forwarding running in VM / remote**:

```bash
kubectl port-forward --address 0.0.0.0 pod/web 8082:80
# Afterwards in browser / curl: http://<node ip>:8082
```

The differentiation between the two cases will not be made for the remainder for this workshop, please ensure to use the correct version of the command.

<details>
<summary>Expected Output</summary>

```text
Forwarding from 127.0.0.1:8082 -> 80
Forwarding from [::1]:8082 -> 80
Handling connection for 8082
```

`curl http://localhost:8082` returns `HTTP 200` and the welcome-to-nginx page.
</details>

**Tip**: if you are using Freelens you can klick on a Pod or Service to open the details-panel on the right. If you scroll down there you can see a button `Forward` next to listed Ports. Klicking this automatically starts a port-forwarding and opens the local port in the Browser.

## Pod with Init-Container

As previously mentioned, a Pod can consist out of multiple containers and init-containers. Let's take a closer look at init-containers.

The manifest below adds an init-container to the nginx Pod. The job of the init-container is to overwrite the HTML-page that nginx ships by default. The nginx Container will only start after all init-containers have terminated successfully:

```bash
kubectl apply -f manifests/pod_nginx_init.yml
```

If you are quick enough, you can see how the init-container runs initially, after which the regular container starts to run:

```bash
kubectl get pod web-multi -w
```

<details>
<summary>Expected Output</summary>

```text
NAME        READY   STATUS     RESTARTS   AGE
web-multi   0/1     Init:0/1   0          1s
web-multi   0/1     PodInitializing   0   3s
web-multi   1/1     Running    0          4s
```
</details>

You can also view the starting sequence afterwards with:

```bash
kubectl describe pod web-multi
```

Here you can see that the Pod is initially scheduled on a node. Afterwards the image is pulled like before. The nginx image should already be present on the node and is thus reused. Then the `init-content` container is started. After termination, the `nginx` container is started.

## View Logs of specific container

If a Pod consists out of multiple containers, `kubectl logs web-multi` will output the logs of the main container. the main container is the first container in the `container` list in the resource manifest. If we want to view the logs of the init contianer, we must pass the `-c init-content` flag:

```bash
kubectl logs web-multi -c init-content
```

<details>
<summary>Expected Output</summary>

```text
Hello to stdout!
```
</details>

## Delete Pod

To delete a pod:

```bash
kubectl delete pod web
kubectl delete -f manifests/pod_nginx.yml
```

Pod termintion can sometimes take some time if containers in a Pod do not immediately quit after receiving the SIGTERM signal. Kubernetes attempts to gracefully shut down the containers, but terminates them forcefully after some time.

## Pod Ephemeralität

We already introduced that Pods are ephermeral, and that they do not have a stable IP address. We can also view this in practice:

```bash
kubectl apply -f manifests/pod_nginx.yml
kubectl get pod -o wide web
kubectl delete pod web
kubectl apply -f manifests/pod_nginx.yml
kubectl get pod -o wide web
```

<details>
<summary>Expected Output</summary>

```text
NAME   READY   STATUS    RESTARTS   AGE     IP            NODE         NOMINATED NODE   READINESS GATES
web    1/1     Running   0          2m19s   172.16.0.11   k3s-ubuntu   <none>           <none>

pod "web" deleted from default namespace
pod/web created

NAME   READY   STATUS    RESTARTS   AGE   IP            NODE         NOMINATED NODE   READINESS GATES
web    1/1     Running   0          3s    172.16.0.12   k3s-ubuntu   <none>           <none>
```
</details>

## Pod Probes

In the introduction, we talked about Kubernetes being "self-healing". However, to repair something you must know whats broken. For this, Kubernetes uses Probes similar to Docker healthchecks. These probes define queries for a container, to, at multiple points in a Pod lifecycle, ask the question: "is this Pod healthy?". In K8s, the ubelet is responsible to periodically check the configured probes, and to report unhealthy Pods to the control plane.

### Probe Types

**Startup Probe**:

The startup probe can be used to check if the application in a container has finished the startup process and is ready to serve requests. Only when the startup probe has been successful, liveness and readiness probes are initiated. The startup probe is sensible if a Pod can take a long time to start up, e.g. because it has to perform a database initialization. When the startup probe fails, the Pod is restarted according to its configured restart policy.

**Readiness Probe**:

The readiness probe checks if a Pod is ready to handle requests. This decides wether K8s routes requests to this Pod at all. If the probe fails, the Pod is automatically excluded from the pool of Pods that are elligeble to handle requests. However, the Pod is not restarted.

**Liveness Probe**:

The liveness probe checks if a Pod is still responsive or alive. For example, a Pod could encounter a deadlock and freeze up. In this case, the Pod is "beyond repair", and must be restarted. The difference to a liveness probe is that a Pod also be temporarily overloaded and thus can also become unresponsive. The Pod is thus not broken, but overloaded. In this case a Pod restart would do more harm than good. When configuring probes, the liveness probe should not be as sensitive as the readiness probe: a misclassification could cause issues as the Pod is continously restarted rather than removing load from it.

### Probe Configuration

All three probe types can be configured with the same fields. The probe type changes the semantics of the probe as described above.

- `initialDelaySeconds`: initial delay to the first probe run after starting the Pod, or in the case of a liveness or startup probe, the time delay since the completion of the startup probe
- `periodSeconds`: intervall in which to run the probe
- `timeoutSeconds`: timeout for probe requests
- `successThreshold`: how often must the probe complete sucessfully after a failure for the Pod to be considered healthy again?
- `failureThreshold`: how often must the probe fail before the Pod is classified unhealthy?
- Handler: `httpGet`, `tcpSocket`, `exec` or `grpc`: how should the container be monitored?

### Interactive Simulator

To test the behavior of different probes, we can use a small [simulator Pod](https://github.com/PhilipJonasFranz/k8s-probe-simulator):

```bash
kubectl apply -f manifests/pod_probe.yml
kubectl port-forward deploy/probe-sim 8088:8080
```

In a second terminal:

```bash
# Get the name of the probe simulator pod
POD=$(kubectl get pod -l app=probe-sim -o jsonpath='{.items[0].metadata.name}')

# Watch the events for this specific pod
kubectl get events --field-selector involvedObject.name=$POD --sort-by='.lastTimestamp' -w
```

Open the UI of the service at `http://localhost:8088`. The Pod of the simulator uses all three probe types. When activting `Return 503`, the readiness probe fails:

<details>
<summary>Expected Output</summary>

```text
0s          Warning   Unhealthy                pod/probe-sim-578bb559b4-k2k5p                                             Readiness probe failed: HTTP probe failed with statuscode: 503
0s          Warning   Unhealthy                pod/probe-sim-578bb559b4-k2k5p                                             Readiness probe failed: HTTP probe failed with statuscode: 503
```
</details>

Additionally we can observe that the Pod IP is removed as available Endpoint for requests:

```bash
kubectl get endpoints -w
```

**Note**: we are still able to view the UI of the Pod since we are port-forwarding the Pod directly. However, requests from within the cluster would first be routed to the service. There, the request would not have an available endpoint to be sent to; hence, the request would fail.

<details>
<summary>Expected Output</summary>

```text
probe-sim               172.16.0.66:8080                               5m6s
probe-sim                                                              5m15s
probe-sim               172.16.0.66:8080                               5m20s
```
</details>

Activating `Return 500` or `Lock up` causes the liveness probe to fail. After some time, the Pod is restarted:

<details>
<summary>Expected Output</summary>

```text
0s          Warning   Unhealthy                pod/probe-sim-578bb559b4-k2k5p                                             Liveness probe failed: HTTP probe failed with statuscode: 500
0s          Warning   Unhealthy                pod/probe-sim-578bb559b4-k2k5p                                             Liveness probe failed: HTTP probe failed with statuscode: 500
0s          Normal    Killing                  pod/probe-sim-578bb559b4-k2k5p                                             Container probe-sim failed liveness probe, will be restarted
0s          Normal    Pulled                   pod/probe-sim-578bb559b4-k2k5p                                             Container image "docker.io/local/probe-sim:latest" already present on machine and can be accessed by the pod
0s          Normal    Created                  pod/probe-sim-578bb559b4-k2k5p                                             Container created
0s          Normal    Started                  pod/probe-sim-578bb559b4-k2k5p                                             Container started
```
</details>

After the Pod was restarted, the startup countdown ticks down. Only after it has completed the app starts to respond with status 200 to the startup probe. If the countdown is paused, the startup of the app is delayed. After some time the startup probe fails, and the Pod is restarted:

<details>
<summary>Expected Output</summary>

```text
0s          Warning   Unhealthy                pod/probe-sim-578bb559b4-k2k5p                                             Startup probe failed: HTTP probe failed with statuscode: 503
0s          Warning   Unhealthy                pod/probe-sim-578bb559b4-k2k5p                                             Startup probe failed: HTTP probe failed with statuscode: 503
0s          Normal    Killing                  pod/probe-sim-578bb559b4-k2k5p                                             Container probe-sim failed startup probe, will be restarted
0s          Normal    Pulled                   pod/probe-sim-578bb559b4-k2k5p                                             Container image "docker.io/local/probe-sim:latest" already present on machine and can be accessed by the pod
0s          Normal    Created                  pod/probe-sim-578bb559b4-k2k5p                                             Container created
0s          Normal    Started                  pod/probe-sim-578bb559b4-k2k5p                                             Container started
```
</details>

## Pod Failure States

Next to probes, other possible failure states can occour around a Pod. K8s implements multiple status-indicators which can show the current state of a Pod. We will briefly investigate some of these states:

**ImagePullBackOff**: the simplest case: the specified container image or tag does not exist:

```bash
kubectl apply -f manifests/pod_nginx_bad_image.yml
kubectl get pod -o wide web-broken
```

**CrashLoopBackOff**: the Pod is repeatedly crashing, e.g. because of a invalid config. The Pod enters the `CrashLoopBackoff` state:

```bash
kubectl apply -f manifests/pod_busybox_crash_loop.yml
kubectl get pods -o wide -w
```

<details>
<summary>Expected Output</summary>

```text
NAME            READY   STATUS             RESTARTS      AGE   IP            NODE         NOMINATED NODE   READINESS GATES
busybox-crash   1/1     Running            0             2s    172.16.0.16   k3s-ubuntu   <none>           <none>
busybox-crash   0/1     Error              0             5s    172.16.0.16   k3s-ubuntu   <none>           <none>
busybox-crash   1/1     Running            1 (1s ago)    6s    172.16.0.16   k3s-ubuntu   <none>           <none>
busybox-crash   0/1     Error              1 (4s ago)    9s    172.16.0.16   k3s-ubuntu   <none>           <none>
busybox-crash   0/1     CrashLoopBackOff   1 (12s ago)   21s   172.16.0.16  k3s-ubuntu   <none>           <none>
busybox-crash   1/1     Running            2 (12s ago)   21s   172.16.0.16  k3s-ubuntu   <none>           <none>
busybox-crash   0/1     Error              2 (16s ago)   25s   172.16.0.16  k3s-ubuntu   <none>           <none>
busybox-crash   0/1     CrashLoopBackOff   2 (26s ago)   50s   172.16.0.16  k3s-ubuntu   <none>           <none>
busybox-crash   1/1     Running            3 (26s ago)   50s   172.16.0.16  k3s-ubuntu   <none>           <none>
busybox-crash   0/1     Error              3 (30s ago)   54s   172.16.0.16  k3s-ubuntu   <none>           <none>
```
</details>

From the output we can observe that the Pod is initially in the state `Running` before it crashes, causing the Pod to enter the `Error` state. Kubernetes restarts the Pod not immediately, but uses a capped exponential back-off timer. This prevents many restarts of the Pod in a short amount of time.

## Pod Resource Limits

Similar to Docker we can also specify resource limits for individual containers. An example can be found in two manifests:

```bash
kubectl apply -f manifests/pod_cpu_bench.yml
kubectl apply -f manifests/pod_memory_hog.yml
```

Two Pods are created. One Pod keeps allocating RAM until it is killed with an out-of-memory status (`OOMKilled`). The other container runs a CPU benchmark with limited CPU resources:

```bash
kubectl logs -f memory-hog
```

<details>
<summary>Expected Output</summary>

```text
belegt: 10 MB
belegt: 20 MB
belegt: 30 MB
belegt: 40 MB
belegt: 50 MB
belegt: 60 MB
```
</details>

```bash
kubectl logs -f cpu-bench
```

<details>
<summary>Expected Output</summary>

```text
runde 1: 817 Iterationen in 10 s
runde 2: 861 Iterationen in 10 s
runde 3: 853 Iterationen in 10 s
runde 4: 856 Iterationen in 10 s
```
</details>

Increasing the CPU resources of the `cpu-bench` Pod:

```bash
kubectl delete pod cpu-bench
kubectl patch --local -f manifests/pod_cpu_bench.yml \
  -p '{"spec":{"containers":[{"name":"bench","resources":{"limits":{"cpu":"500m"}}}]}}' \
  -o yaml | kubectl apply -f -
kubectl logs -f cpu-bench
```

Now the benchmark in the Pod manages much more iterations:

<details>
<summary>Expected Output</summary>

```text
runde 1: 4079 Iterationen in 10 s
runde 2: 4474 Iterationen in 10 s
runde 3: 4497 Iterationen in 10 s
runde 4: 4499 Iterationen in 10 s
```
</details>

## Cleanup

```bash
bash cleanup.sh
```

Continue with [Labels & Annotationen](04-labels-annotations.md).
