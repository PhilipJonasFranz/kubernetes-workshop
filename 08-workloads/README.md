# Workloads

In the previous chapters we manually created and deleted Pods. We also learned that a service with multiple endpoints effectively acts like a load-balancer. In this chapter, we will take a look at the different workload types. Workloads can be understood as a management and automation layer for Pods. Using workloads, we can run multiple replicas of the same Pod, and scale dynamically, to achieve resilience and high-availability. 

Kubernetes defines multiple workload types: for stateless workloads, the `ReplicaSet` and `Deployment`, for stateful workloads the `StatefulSet`. Additionally, the `DaemonSet` for tasks that should run on all nodes, and `Job` and `CronJob` types for one-shot or scheduled, recurring tasks. We will take a look at all six types in this order.

## ReplicaSet

The simplest workload type is the `ReplicaSet`: based on a Pod template, `N` replicas are created. If one of the Pod crashes, it is removed and a new replica takes its place. The `ReplicaSet` should only be used for stateless workloads, for reasons we will see later.

```bash
kubectl apply -f manifests/replicaset.yml
kubectl get pods -l app=web-rs -o wide
```

<details>
<summary>Expected Output</summary>

```text
NAME           READY   STATUS    RESTARTS   AGE   IP
web-rs-ndqx4   1/1     Running   0          3s    172.16.0.42
web-rs-nlqw4   1/1     Running   0          3s    172.16.0.43
web-rs-wts24   1/1     Running   0          3s    172.16.0.41
```
</details>

We can see that 3 replicas have been started. The name of the Pod is composed out of the name of the `ReplicaSet`, concatenated with a random hash to prevent name collisions. If we delete one of the Pods:

```bash
kubectl delete pod web-rs-<hash>
```

We can see that a new Pod has taken its place (pay attention to the `Age` column):

```bash
kubectl get pods -l app=web-rs -o wide
```

<details>
<summary>Expected Output</summary>

```text
NAME           READY   STATUS    RESTARTS   AGE   IP            NODE         NOMINATED NODE   READINESS GATES
web-rs-fmntn   1/1     Running   0          5s    172.16.0.72   k3s-ubuntu   <none>           <none>
web-rs-n6ftf   1/1     Running   0          69s   172.16.0.69   k3s-ubuntu   <none>           <none>
web-rs-pml2c   1/1     Running   0          69s   172.16.0.71   k3s-ubuntu   <none>           <none>
```
</details>

### Scaling a ReplicaSet

You can manually scale the `ReplicaSet`:

```bash
kubectl scale replicaset/web-rs --replicas=5
kubectl get pods -l app=web-rs
```

### Pod Placement & Scheduling

Kubernetes automatically distributes Pods on different nodes to balance the load. Based on the existing load, it is possible that Pods are scheduled on the same node. In the case of a highly-available database, which uses e.g. 3 replicas, such that the failure of one replica can be tolerated, replicas must not be scheduled on the same node to not introduce an artifacial point of failure. For that, Kubernetes provides mechanisms to influence the behavior of the scheduler.

- **nodeSelector / Node-Affinity**: which nodes are allowed (node properties)
- **Pod-Affinität/Anti-Affinity**: placement relative to other Pods
- **Topology Constraints**: distribution of Pods on allowed nodes
- **Taints/Tolerations**: Pods are not scheduled on nodes, unless Pod permits it

The different behaviors can be combined to ensure the desired topology is always created. Lets take a look at a few examples:

**One Pod per Node**

To ensure at most one Pod per node is placed, Pod Anti-Affinity can be used:

```bash
kubectl apply -f manifests/replicaset_anti_affinity.yml
kubectl get pods -o wide
```

The `ReplicaSet` specifies 4 replicas, however, since the cluster only has three nodes, one Pod remains in the state `Pending`, as it cannot be scheduled.

**All Pods on the same node**

To place all pods on the same node, a node selector can be used:

```bash
# Extract name of first node
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# Substitute node name in manifest and apply it
sed "s/kubernetes.io\/hostname: .*/kubernetes.io\/hostname: $NODE/" manifests/replicaset_pinned.yml | kubectl apply -f -

kubectl get pods -o wide
```

**Pod Co-location**

To co-locate one Pod with another, for example to reduce inter-node network traffic, pod affinity can be used:

```bash
kubectl apply -f manifests/replicaset_twins.yml
kubectl get pods -o wide
```

**Even Distribution**

To ensure the distribution of Pods between nodes is even, we can use topology spread constraints:

```bash
# Get Node Names, e.g. k3s-ubuntu-1, k3s-ubuntu-2, k3s-ubuntu-3
kubectl get nodes

# Zwei von drei Nodes labeln
kubectl label node k3s-ubuntu-1 topology.kubernetes.io/zone=zoneA
kubectl label node k3s-ubuntu-2 topology.kubernetes.io/zone=zoneB

kubectl apply -f manifests/replicaset_spread.yml
kubectl get pods -o wide
```

Initially, Pods are only scheduled on nodes `k3s-ubuntu-1` and `k3s-ubuntu-2`, since `k3s-ubuntu-3` is missing the required zone label. If we also label the third node:


```bash
kubectl label node k3s-ubuntu-3 topology.kubernetes.io/zone=zoneC

# Delete all pods to schedule them again
kubectl delete pods -l app=web-rs-spread

kubectl get pods -o wide
```

we can see that the Pods have now been distributed on all three nodes equally.

### Deleting a ReplicaSet

When deleting a `ReplicaSet`, all associated Pods are deleted as well:

```bash
kubectl delete -f manifests/replicaset.yml
```

## Deployment

The `ReplicaSet` in itself is fairly primitive: it maintains a pre-determined number of replicas, without considering the required capacity. The `Deployment` type extends the `ReplicaSet`, but adds additional "intelligence". This includes e.g. update-strategies, which determine how Pods are replaced if the `Deployment` is updated to a new image version, or the option to rollback a `Deployment` if something went wrong.

`Deployments`, like `ReplicaSets`, can only be used for stateless workloads.

```bash
kubectl apply -f manifests/deployment.yml
```

Again, 3 replicas are created:

```bash
kubectl get pods
```

However, we can also see that again a `ReplicaSet` is created. If we inspect it we can see that it is being controlled by the created `Deployment`:

```bash
kubectl get replicasets
kubectl describe rs web-deployment-<hash>
```

The name of the `ReplicaSet` is constructed by the name of the deployment with a random hash. The names of the Pods in turn is given by the name of the `ReplicaSet`, and another random hash.

<details>
<summary>Expected Output</summary>

```text
NAME                        DESIRED   CURRENT   READY   AGE
web-deployment-6fb665c7cb   3         3         3       3m50s

[...]
Controlled By:  Deployment/web-deployment
Replicas:       3 current / 3 desired
Pods Status:    3 Running / 0 Waiting / 0 Succeeded / 0 Failed
[...]
```
</details>

### Rolling Update

As previously mentioned, a `Deployment` adds additional intelligence on top of the `ReplicaSet`. One example is the rolling update. The rolling update controls how Pods get replaced after a `Deployment` has been changed, to prevent all Pods being restarted at the same time, resulting in service downtime. Instead, the rolling update replaces one Pod after the other, until all Pods have been replaced.

The `Deployment` we created earlier uses an old nginx image. We want to update it to the `latest` tag. In your terminal, watch the state of the Pods:

```bash
kubectl get pods -w
# or
kubectl rollout status deployment/web-deployment
```

Open a second terminal. Now we update the image of the deployment to `latest`, which triggers the rolling update:

```bash
kubectl set image deployment/web-deployment nginx=nginx:latest
```

<details>
<summary>Expected Output</summary>

```text
NAME                             READY   STATUS    RESTARTS   AGE
web-deployment-d86cbcb98-gjfc9   0/1     Running   0          6s
web-deployment-d86cbcb98-h56ss   0/1     Running   0          6s
web-deployment-d86cbcb98-t5qpn   0/1     Running   0          6s
web-deployment-6fb86b7f55-ps5z6   0/1     Pending   0          0s
web-deployment-6fb86b7f55-ps5z6   0/1     Pending   0          0s
web-deployment-6fb86b7f55-ps5z6   0/1     ContainerCreating   0          0s
web-deployment-6fb86b7f55-ps5z6   0/1     ContainerCreating   0          0s
web-deployment-d86cbcb98-h56ss    1/1     Running             0          11s
web-deployment-d86cbcb98-t5qpn    1/1     Running             0          11s
web-deployment-6fb86b7f55-ps5z6   0/1     Running             0          0s
web-deployment-d86cbcb98-gjfc9    1/1     Running             0          12s
web-deployment-6fb86b7f55-ps5z6   1/1     Running             0          6s
[...]
web-deployment-6fb86b7f55-hbk98   0/1     Running             0          1s
web-deployment-d86cbcb98-h56ss    0/1     Completed           0          25s
web-deployment-d86cbcb98-h56ss    0/1     Completed           0          25s
web-deployment-6fb86b7f55-hbk98   1/1     Running             0          7s
web-deployment-d86cbcb98-gjfc9    1/1     Terminating         0          31s
web-deployment-d86cbcb98-gjfc9    1/1     Terminating         0          31s
web-deployment-d86cbcb98-gjfc9    0/1     Completed           0          32s
web-deployment-d86cbcb98-gjfc9    0/1     Completed           0          32s
web-deployment-d86cbcb98-gjfc9    0/1     Completed           0          32s


Waiting for deployment "web-deployment" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "web-deployment" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "web-deployment" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "web-deployment" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "web-deployment" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "web-deployment" rollout to finish: 1 old replicas are pending termination...
deployment "web-deployment" successfully rolled out
```
</details>

Based on the output we can see that a new `ReplicaSet` is created (note the new `web-deployment-<hash>`), since the `Deployment` was changed. Then the old `ReplicaSet` is incrementally scaled down, terminating old Pods, while at the same time, the new `ReplicaSet` is scaled up, creating new, updated Pods.

The `readinessProbe` we defined earlier in the `deployment.yml` manifest delays this process artifacially by 5 seconds (`initialDelaySeconds`), as the rolling update ensures that new Pods are healthy before continuing to update more Pods. This also enables us to inspect experience the rolling update step by step.

#### Rollout-History and Rollback

Another feature of `Deployments` is the ability to rollback an update. A `Deployment` stores a limited number of revisions:

```bash
kubectl rollout history deployment/web-deployment
```

<details>
<summary>Expected Output</summary>

```text
deployment.apps/web-deployment
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```
</details>

If we want to rollback a deployment to a previous version:

```bash
kubectl rollout undo deployment/web-deployment
```

<details>
<summary>Expected Output</summary>

```text
Warning: resource deployments/web-deployment was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/web-deployment rolled back
```

The warning is informative: `rollout undo` and `apply` both write in `spec.template`, but only `apply` also updates the last-applied-configuration annotation. After an `undo` one should not use `apply` afterwards with the old manifest.
</details>

After some time, all Pods were rolled back. If we inspect one of the Pods we can see that we are back one the `nginx:1.27` image version:

```bash
kubectl describe pod web-deployment-d86cbcb98-6xpd8 | grep Image
```

<details>
<summary>Expected Output</summary>

```text
    Image:          nginx:1.27
    Image ID:       docker.io/library/nginx@sha256:...
```
</details>

### Deleting a Deployment

Similar to the `ReplicaSet`, if a `Deployment` is deleted, the associated `ReplicaSet` and all associated Pods of the `ReplicaSet` are deleted:

```bash
kubectl delete -f manifests/deployment.yml
kubectl get rs,pods -l app=web-deploy
```

<details>
<summary>Expected Output</summary>

```text
deployment.apps "web-deployment" deleted from default namespace
No resources found in default namespace.
```
</details>

## StatefulSet

Until now we looked at workload types for stateless workloads. The `StatefulSet` is, as the name implies, meant for stateful workloads. Functionally, its very similar to a `Deployment`, however, the `StatefulSet` assigns each Pod a stable, persistent identity. Pods remain ephermeral, but they are not assigned random names, but predictable, enumerated names (`web-stateful-0`, `web-stateful-1`, ...). This is important, as after a Pod restart, an existing volume is associated with the same Pod-Identity again.

Next to the stable storage identity, the `StatefulSet` also assigns stable network identities - but more on that later in the section about Headless Services. Lets first start by creating a `StatefulSet`:

```bash
kubectl apply -f manifests/statefulset.yml
```

We can inspect all of the created resources in one go by selecting them via a label:

```bash
kubectl get statefulset,pod,pvc -l app=web-stateful
```

Two pods have been created. The names of the Pods are based on the name of the `StatefulSet`, postfixed with an increasing number, not a random hash. In a similar way, the `PersistentVolumeClaims` use predictable names. The names result in a 1-to-1 mapping: if a Pod of a `StatefulSet` gets deleted or recreated, it can automatically match with the same `PersistentVolumeClaim`. This is important for e.g. a distributed hash table, where each node of the hash table stores different data, in which case the volumes of the nodes must not get mixed up to ensure data is still located at the same, predictable location. This is also the reason why the `ReplicaSet` and `Deployment` are not suitable for stateful workloads; they do not enforce this type of consistency between storage and compute.

<details>
<summary>Expected Output</summary>

```text
NAME                            READY   AGE
statefulset.apps/web-stateful   2/2     46s

NAME                 READY   STATUS    RESTARTS   AGE
pod/web-stateful-0   1/1     Running   0          46s
pod/web-stateful-1   1/1     Running   0          37s

NAME                                        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-web-stateful-0   Bound    pvc-9c244588-946d-4bc3-829b-ef790146a5da   500Mi      RWO            longhorn       <unset>                 2m57s
persistentvolumeclaim/data-web-stateful-1   Bound    pvc-cfbce171-99a1-4f0c-bb2e-d258e49a3840   500Mi      RWO            longhorn       <unset>                 2m45s
```
</details>

### Scaling a StatefulSet

If we scale a `StatefulSet`, we can see that additional `PersistentVolumeClaims` get created as well:

```bash
kubectl scale statefulset/web-stateful --replicas=3
kubectl get statefulset,pod,pvc -l app=web-stateful
```

If we scale the `StatefulSet` down, the `PersistentVolumeClaims` are kept:

```bash
kubectl scale statefulset/web-stateful --replicas=2
```

This is intended - if we decide to scale up later, the new Pods will match with the existing volumes. However, this also requires application-level support, e.g. to sync the replicas back up, i.e. to update the stale data if the set was scaled down for a long time.

### Headless Services

We have seen how the `StatefulSet` takes care of a storage and Pod identity, however, one small Problem remains: Pods themselves dont have a stable IP address - this is also true for Pods controlled by a `StatefulSet`. However, distributed workloads must coordinate, and thus need a mechanism to query the IP of other replicas. However, we also learned that Pods dont receive a DNS name, unlike a service. What we need is a DNS-name per Pod identity, such that Pods can resolve the name to the Pod IP. For this purpose, headless services exist:

```bash
kubectl apply -f manifests/service_headless.yml
```

If we inspect the service we can see that it does not have a cluster-internal IP:

```bash
kubectl get svc
```

<details>
<summary>Expected Output</summary>

```text
NAME           TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
web-stateful   ClusterIP   None          <none>        80/TCP    59s
```
</details>

However, we can send requests to each individual Pod of the `StatefulSet` by resolving the Pod-Name to IP addresses via DNS:

```bash
kubectl apply -f manifests/pod_debug_netshoot.yml
kubectl exec -it netshoot -- bash
netshoot:~# dig web-stateful-0.web-stateful.default.svc.cluster.local
```

<details>
<summary>Expected Output</summary>

```text
; <<>> DiG 9.20.23 <<>> web-stateful-0.web-stateful.default.svc.cluster.local
;; global options: +cmd
;; Got answer:

[...]

;; QUESTION SECTION:
;web-stateful-0.web-stateful.default.svc.cluster.local. IN A

;; ANSWER SECTION:
web-stateful-0.web-stateful.default.svc.cluster.local. 5 IN A 172.16.0.102
```
</details>

## DaemonSet

The `DaemonSet` ensures that exactly one Pod is running on each K8s node in the cluster. This can be e.g. sensible for administrative or monitoring tasks:

```bash
kubectl apply -f manifests/daemonset.yml
kubectl get pods -l app=node-agent -o wide
kubectl get nodes
```

<details>
<summary>Expected Output</summary>

```text
NAME               READY   STATUS    RESTARTS   AGE   IP            NODE         NOMINATED NODE   READINESS GATES
node-agent-b26zf   1/1     Running   0          9s    172.16.0.99   k3s-ubuntu   <none>           <none>

NAME         STATUS   ROLES                AGE   VERSION
k3s-ubuntu   Ready    control-plane,etcd   9h    v1.36.2+k3s1
```
</details>

If another node is added to cluster later, a new Pod will be automatically started on the new node.

## Job

The `Job` workload type is intended to be used for one-shot tasks. A single Pod is restarted until it terminates without errors, i.e. the job has been completed successfully, or the maximum number of restarts is reached:

```bash
kubectl apply -f manifests/job.yml
kubectl get jobs -w
```

<details>
<summary>Expected Output</summary>

```text
job.batch/hello-job created

NAME        STATUS    COMPLETIONS   DURATION   AGE
hello-job   Running   0/1           8s         8s
hello-job   SuccessCriteriaMet   0/1           8s         8s
hello-job   Complete             1/1           8s         8s
```
</details>

After the `Job` completes, the Pod is not deleted, but kept in the state `Completed`:

```bash
kubectl get pods
kubectl logs -l job-name=hello-job
```

## CronJob

The `CronJob` is similar to the normal `Job`, but is started periodically based on the defined schedule, which is in this case given by a cron-expression:

```bash
kubectl apply -f manifests/cronjob.yml
```

We can view the job history with:

```bash
kubectl get cronjob hello-cron
kubectl get pods
kubectl logs hello-cron-29748730-dzst6
```

<details>
<summary>Expected Output (after first completion, i.e. 1 minute)</summary>

```text
NAME         SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
hello-cron   */1 * * * *   <none>     False     0        24s             66s

NAME                        READY   STATUS      RESTARTS   AGE
hello-cron-29748730-dzst6   0/1     Completed   0          27s

Fri Jul 24 20:10:00 UTC 2026
Hello from CronJob
```
</details>

## Cleanup

```bash
bash cleanup.sh
```

Continue with [Service Accounts & RBAC](09-rbac.md).
