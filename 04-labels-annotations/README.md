# Metadata, Labels & Annotations

K8s resource manifests carry metadata, and optionally labels and annotations. All of these fields are key-value maps. Where are the differences, and for what are they used?

Let's take a look at a sample manifest:

```bash
kubectl get deployment -n kube-system coredns -o yaml
```

Shortened excerpt:

```yaml
kind: Deployment
apiVersion: apps/v1
metadata:
  name: coredns
  namespace: kube-system
  uid: a14aab53-2692-41b1-9e8f-98f9d20290ff
  resourceVersion: '558'
  generation: 1
  creationTimestamp: '2026-07-24T10:16:38Z'
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: CoreDNS
    objectset.rio.cattle.io/hash: bce283298811743a0386ab510f2f67ef74240c57
  annotations:
    deployment.kubernetes.io/revision: '1'
    objectset.rio.cattle.io/applied: >-
      H4sIAAAAAAAA/6xVU [...]
    objectset.rio.cattle.io/id: ''
    objectset.rio.cattle.io/owner-gvk: k3s.cattle.io/v1, Kind=Addon
    objectset.rio.cattle.io/owner-name: coredns
    objectset.rio.cattle.io/owner-namespace: kube-system
[...]
```

This manifest describes a resource of type `Deployment`, which we will get to know later. In the manifest we can find the field `metadata`, as well as the fields `labels` and `annotations` as nested fields of `metadata`.

The fields of `metadata` are part of the fixed schema of the API resource, which describes how the `.yaml` data must look like, and is not extensible. We can view the documentation of the `metadata` field using `kubectl explain`:

```bash
kubectl explain deployment.metadata
```

Kubernetes uses the `metadata` field to store internal data. Most relevant are the `name` and `namespace` fields, which define the name of the resource and in which namespace the resource is located in. But also when the resource was created, how often it was modified is stored here. The fields are automatically updated managed, i.e. when creating or updating the resource. The `labels` and `annotations` fields are also part of the fixed schema, however, their content is an extensible key-value map, which we can use to store additional key-value data.

In this chapter we will take a look at the differences and use-cases of `labels` and `annotations` in more detail.

## Labels

The `labels` field defines labels which can be used to _select_ resources. Resource selection means that we use labels to identify a subset of all resources. We will see how that looks in practise shortly. The difference of the `labels` field to other `metadata` fields is that we can extend the content of the map freely, while others are constrained. Additionaly, labels are typically managed by us, not Kubernetes, with the exception of some standard labels which are assigned to resources automatically.

To experiment with resource selection, we re-create the `production` and `staging` namespaces from chapter 1. However, this time we focus on their labels:

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

### Show resource labels

To view the labels of a resource, you can pass the `--show-labels` flag:

```bash
kubectl get namespaces --show-labels
```

<details>
<summary>Expected Output</summary>

```text
NAME              STATUS   AGE   LABELS
default           Active   3m    kubernetes.io/metadata.name=default
kube-node-lease   Active   3m    kubernetes.io/metadata.name=kube-node-lease
kube-public       Active   3m    kubernetes.io/metadata.name=kube-public
kube-system       Active   3m    kubernetes.io/metadata.name=kube-system
production        Active   5s    env=production,kubernetes.io/metadata.name=production,owner=myself
staging           Active   5s    env=staging,kubernetes.io/metadata.name=staging,owner=myself
```
</details>

Labels can also be formatted as additional output columns:

```bash
kubectl get namespaces -L env -L owner
```

<details>
<summary>Expected Output</summary>

```text
NAME              STATUS   AGE   ENV          OWNER
default           Active   3m
kube-node-lease   Active   3m
kube-public       Active   3m
kube-system       Active   3m
production        Active   5s    production   myself
staging           Active   5s    staging      myself
```
</details>

### Selecting Resources using Labels

Now we will take a look at label selection. The use-case of label selection is to group and filter resources. For example, we can list all namespaces that carry a specific label value, or the ones who do not carry a specific value:

```bash
kubectl get namespaces -l owner=myself
kubectl get namespaces -l owner!=myself
```

<details>
<summary>Expected Output</summary>

```text
NAME         STATUS   AGE
production   Active   5s
staging      Active   5s

NAME              STATUS   AGE
default           Active   3m
kube-node-lease   Active   3m
kube-public       Active   3m
kube-system       Active   3m
```
</details>

Its also possible to select by multiple labels at the same time:

```bash
kubectl get namespaces -l env=production,owner=myself
```

Its also possible to filter by multiple label values using a set:

```bash
kubectl get namespaces -l 'env in (production,staging)'
kubectl get namespaces -l 'env notin (production,staging)'
```

<details>
<summary>Expected Output</summary>

Both return `production` and `staging`, and everything except these two in the second case, analogous to the equality selectors above.
</details>

We can also select multiple resource types at the same time. This is specifically useful to show all objects that are associated with a specific app:

```bash
kubectl get all -l k8s-app=kube-dns -A
```

<details>
<summary>Expected Output</summary>

```text
NAMESPACE     NAME                           READY   STATUS    RESTARTS      AGE
kube-system   pod/coredns-5f5694d56b-2vq5n   1/1     Running   1 (18m ago)   25h

NAMESPACE     NAME               TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)                  AGE
kube-system   service/kube-dns   ClusterIP   172.16.64.10   <none>        53/UDP,53/TCP,9153/TCP   25h

NAMESPACE     NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
kube-system   deployment.apps/coredns   1/1     1            1           25h

NAMESPACE     NAME                                 DESIRED   CURRENT   READY   AGE
```
</details>

### Check for Label Existence

```bash
kubectl get namespaces -l tier
kubectl get namespaces -l '!tier'
```

<details>
<summary>Expected Output</summary>

```text
No resources found

NAME              STATUS   AGE
default           Active   3m
kube-node-lease   Active   3m
kube-public       Active   3m
kube-system       Active   3m
production        Active   5s
staging           Active   5s
```

No namespace has the label called `tier`, which is why no resources are found with the first query.
</details>

### Modifying a Label of an existing Resource

While Labels can be set as part of a resource manifest, its also possible to label, unlabel and relabel a resource using `kubectl` after it was created:

```bash
kubectl label namespace staging team=devs
kubectl label namespace staging team=qa --overwrite
```

<details>
<summary>Expected Output</summary>

```text
namespace/staging labeled
namespace/staging labeled
```
</details>

To remove the label `team`:

```bash
kubectl label namespace staging team-
```

<details>
<summary>Expected Output</summary>

```text
namespace/staging unlabeled
```
</details>

### Deleting based on Labels

Labels can also be used to identify resources that shall be deleted. For example, to delete all namespaces which carry the label `owner=myself`, so `production` and `staging`:

```bash
kubectl delete namespace -l owner=myself
```

<details>
<summary>Expected Output</summary>

```text
namespace "production" deleted
namespace "staging" deleted
```
</details>

## Annotations

Annotations, compared to labels, can have a semantic meaning. The field `annotations` is like the `labels` field extensile. However, annotation are not meant to be used to select resource, but to store structured additional data. This data can be used and processed by other entities in the cluster. For example, [External-DNS](https://github.com/kubernetes-sigs/external-dns) uses annotations to automatically generate DNS-entries from ingress routes.

So annotations are a mechanism to extend Kubernetes without having to modify or extend the core API.

### View Annotations

```bash
kubectl get deployment -n kube-system coredns -o jsonpath='{.metadata.annotations}'
```

<details>
<summary>Expected Output (Formatted)</summary>

```json
{
    "deployment.kubernetes.io/revision":"1",
    "objectset.rio.cattle.io/applied":"H4sIAAAAAA [...] DT8KAAA",
    "objectset.rio.cattle.io/id":"",
    "objectset.rio.cattle.io/owner-gvk":"k3s.cattle.io/v1, Kind=Addon",
    "objectset.rio.cattle.io/owner-name":"coredns",
    "objectset.rio.cattle.io/owner-namespace":"kube-system"
}
```

Here we can see the annotations that we already in the manifest at the start of the chapter, but JSON formatted. Some annotations are set by Kubernetes automatically.
</details>

### Create / Delete Annotations

```bash
kubectl annotate namespace default owner=team-alpha --overwrite
kubectl annotate namespace default owner-
```

<details>
<summary>Expected Output</summary>

```text
namespace/default annotated
namespace/default annotated
```

After annotating the resource we can see that `"owner":"team-alpha"` is shown in the JSON output from before, after removing the annotation it is removed again.
</details>

### Effects of Annotations

Lets briefly take a look at what effects annotations can have. The annotation `kubectl.kubernetes.io/default-container` gives `kubectl` a hint which container is considered the default container to show logs from if we dont explicitly specify it. 

Lets create a Pod:

```bash
kubectl apply -f manifests/pod_annotated.yml
```

If the logs are queried, we get the logs from the nginx container:

```bash
kubectl logs annotation-demo
```

However, if we add the annotation and query the logs again, we now get the logs of the sidecar container:

```bash
kubectl annotate pod annotation-demo kubectl.kubernetes.io/default-container=sidecar
kubectl logs annotation-demo
```

While simple, this example still demonstrates the idea of annotations. There are countless annotations, many external plugins and addons use them, as they can inject data into K8s objects without modifying the API schema. Based on the existence of annotations, different actions / behavior is then implemented.

## Cleanup

```bash
bash cleanup.sh
```

Continue with [Services](05-services.md).
