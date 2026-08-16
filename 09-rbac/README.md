# Service Accounts & RBAC

In this chapter we will look at the role-based access-control (RBAC) system of Kubernetes. This system enables users within and outside of the cluster to access allowed cluster-resources - both in a reading or writing manner. The permissions are very granular: different access-modes (e.g. read, write, etc.), permissions for individual resource types, groups of resource types, or all resources.

Permissions are bundled in roles, which are then mapped to service accounts.

## Service Account

A `ServiceAccount` is an identity which receives credentials to authenticate at the cluster API. However, other than a normal user, this account is not meant for users, but for internal usage, e.g. to allow automations to take place.

To start, we create a new service account, which initially has no permissions:

```bash
kubectl apply -f manifests/serviceaccount.yml
```

Afterwards we create a new Pod, which we assign the `ServiceAccount` to:

```bash
kubectl apply -f manifests/pod_kubectl.yml
```

If we now connect to the Pod, we can use kubectl to send a Pod to the cluster API from within the cluster:

```bash
kubectl exec -it kubectl-pod -- sh
sh-5.3$ kubectl get pods
```

<details>
<summary>Expected Output</summary>

```text
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:default:customaccount" cannot list resource "pods" in API group "" in the namespace "default"
```
</details>

We get an error, since the `ServiceAccount` we created has no permissions at all.

## Roles & ClusterRoles

To assign permissions to the `ServiceAccount`, we must first create a `Role`. As stated in the introduction, `Roles` can grant permissions very granulary. The `Role` bundles multiple rules, which identify an API group and contained API resources, e.g. `Pods`, and assign so-called verbs, which encode different modes of access to this resource:

- `create`: create new resource of this type
- `delete`: delete single resource of this type
- `deletecollection`: delete multiple resources of this type (e.g. with label selection)
- `get`: get details for a single resource
- `list`: get list of all resources of this type
- `patch`: modify parts of an existing resource
- `update`: replace an existing resource completely
- `watch`: receive streamed updates if a resource of this type is created, deleted or modified in any way

We create two `Roles`: one grants reading access to the `Pod` resource type, the other grants writing access:

```bash
kubectl apply -f manifests/roles.yml
```

<details>
<summary>Expected Output</summary>

```text
role.rbac.authorization.k8s.io/pod-reader created
role.rbac.authorization.k8s.io/pod-writer created
```
</details>

The `ClusterRole` resource is equivalent to the `Role` resource, except that it is not namespaced:

```bash
kubectl apply -f manifests/clusterrole.yml
```

## RoleBinding & ClusterRoleBinding

To map a `Role` to a `ServiceAccount`, we must create a resource of type `RoleBinding`. Analogous for the `ClusterRole`, we must create a `ClusterRoleBinding`. 

To start, we grant the `customaccount` read-permissions for the `Pod` resource:

```bash
kubectl apply -f manifests/rolebinding_pod_read.yml
```

If we now connect again to the Pod that has the `ServiceAccount` assigned, we can now query Pods in the cluster:

```bash
kubectl exec -it kubectl-pod -- sh
sh-5.3$ kubectl get pods
```

<details>
<summary>Expected Output</summary>

```text
NAME             READY   STATUS    RESTARTS   AGE
kubectl-pod      1/1     Running   0          9m43s
netshoot         1/1     Running   0          23m
web-stateful-0   1/1     Running   0          24m
web-stateful-1   1/1     Running   0          24m
```
</details>

However, we cannot create new Pods:

```bash
sh-5.3$ kubectl run web --image=nginx:stable
```

<details>
<summary>Expected Output</summary>

```text
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:default:customaccount" cannot create resource "pods" in API group "" in the namespace "default"
```
</details>

If we add the required `Role` using a `RoleBinding`, it works:

```bash
kubectl apply -f manifests/rolebinding_pod_write.yml
kubectl exec -it kubectl-pod -- sh
sh-5.3$ kubectl run web --image=nginx:stable
```

We can even see from within the Pod that the Pod was created since we have reading access to `Pods`:

```bash
kubectl get pods
```

<details>
<summary>Expected Output</summary>"

```text
pod/web created

NAME             READY   STATUS    RESTARTS   AGE
kubectl-pod      1/1     Running   0          12m
web              1/1     Running   0          11s
```
</details>

To assign a `ClusterRole`, we must create a `ClusterRoleBinding`:

We can now list the nodes of the cluster from within our debug Pod:

```bash
kubectl apply -f manifests/clusterrolebinding.yml
kubectl exec -it kubectl-pod -- sh
sh-5.3$ kubectl get nodes
```

<details>
<summary>Expected Output</summary>

```text
NAME                STATUS   ROLES                AGE   VERSION
k3s-ubuntu          Ready    control-plane,etcd   10h   v1.36.2+k3s1
```
</details>

## Cleanup

```bash
bash cleanup.sh
```

Continue with [Custom Resources & Custom Controller](10-crds-controllers.md).
