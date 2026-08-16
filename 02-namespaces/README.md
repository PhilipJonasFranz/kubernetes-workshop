# Namespaces

Namespaces in K8s are primarily used to organize and group resources, **not** to isolate them. Namespaces can however be used as selector to isolate resources using `NetworkPolicies`, but this is not the default.

K8s differentiates between resources that are _namespaced_ and _not namespaced_. Based on the name, resources that are _namespaced_ are bound to the scope of a namespace, and are only visible within their namespace. Analogous, resource that are not namespaced are visible from all namespaces.

Every cluster has a `default` namespace, which is used for resources that do not explicitly state a different namespace.

## Create a Namespace

Let's create a few namespaces:

```bash
kubectl apply -f manifests/namespaces.yml
```

<details>
<summary>Expected Output</summary>

```text
namespace/production created
namespace/staging created
```
</details>

## List Namespaces

Namespaces can be listed using:

```bash
kubectl get namespaces
```

Or with the abbreviation:

```bash
kubectl get ns
```

<details>
<summary>Expected Output</summary>

```text
NAME              STATUS   AGE
default           Active   7m27s
kube-node-lease   Active   7m27s
kube-public       Active   7m27s
kube-system       Active   7m27s
production        Active   53s
staging           Active   53s
```
</details>

## Setting the Default-Namespace for the Context

To show resources in a namespace that is not the `default`-namespace, you must pass the `-n <namespace>` argument in `kubectl`:

```bash
kubectl get pods -n kube-system
```

Alternatively, the `--all-namespaces` or `-A` flags show resources in all namespaces.

However, this is tedious. You can change the default namespace that kubectl uses using this command:

```bash
kubectl config set-context --current --namespace=staging
```

<details>
<summary>Expected Output</summary>

```text
Context "default" modified.
```
</details>

To show the current default namespace:

```bash
kubectl config view --minify | grep namespace
```

<details>
<summary>Expected Output</summary>

```text
    namespace: staging
```
</details>

To revert the namespace back to `default`:

```bash
kubectl config set-context --current --namespace=default
```

## Namespaced vs. Cluster-scoped Resources

As previously mentioned, Kubernetes defines resource types that are namespaced and not namespaced. The `Pod` resource is namespaced, which causes the following two commands to return different outputs:

```bash
kubectl get pods -n staging
kubectl get pods -n kube-system
```

You can list all resource types on the server, and filter based on whether they are namespaced or not:

```bash
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
```

<details>
<summary>Expected Output (Excerpt)</summary>

```text
NAME          SHORTNAMES   APIVERSION   NAMESPACED   KIND
configmaps    cm           v1           true         ConfigMap
endpoints     ep           v1           true         Endpoints
events        ev           v1           true         Event
...
NAME                 SHORTNAMES   APIVERSION   NAMESPACED   KIND
componentstatuses    cs           v1           false        ComponentStatus
namespaces           ns           v1           false        Namespace
nodes                no           v1           false        Node
persistentvolumes    pv           v1           false        PersistentVolume
...
```
</details>

Here you can also see the abbreviations associated with resource types, which can also be used in kubectl. For namespaces, we already demonstrated the abbreviation `ns`.

## Deleting a Namespace

To delete a namespace or more generally any resource, you can either delete the resource by specifying the name and type:

```bash
kubectl delete ns <name>
```

Or by passing in the file the resource was created with, which contains the name and type of the resource:

```bash
kubectl delete -f manifests/namespaces.yml
```

If a namespace is deleted, all namespaced resources contained in that namespace are deleted as well. Some resources have so-called "Finalizers", which are meant to ensure that resources are propery cleaned-up when deleting them. For some resources, this can take some time, in rare cases it can get stuck, which causes the deletion of the namespace to be delayed as well. However, after being marked for deletion, the namespace will be deleted once all resources have been cleaned up.

Continue with [Pods](03-pods.md).
