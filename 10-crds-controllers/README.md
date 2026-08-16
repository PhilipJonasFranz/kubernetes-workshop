# Custom Resources & Custom Controllers

In this chapter we will investigate how we can extend the API of Kubernetes. Until now we have mostly looked at resources of the core API: `Pods`, `Services`, etc. The data-schema of these manifests describes a well-defined API: data can be stored and retrieved in a structured way. Additionally, the data is persisted in `etcd`.

However, there are cases in which you would want to specify your own resource types: to store user-defined Data, and to implement custom control-plane behavior into Kubernetes, to enable automations and integrations inside the cluster.

For this purpose, Kubernetes ships with a core API resource called `CustomResourceDefinition` (CRD). Creating a CRD resource in the cluster registers a new, custom resource at the cluster API. Afterwards, this custom resource can be created, queried and deleted like any other core API resource. Additionally, since Kubernetes treats these custom resources like native resources, systems like RBAC also work with custom resource types.

In this chapter we will use the official CRD- and custom controller example from Kubernetes: [sample-controller](https://github.com/kubernetes/sample-controller).

## Custom Ressourcen

Let's start with custom resources. As mentioned in the introduction, resources defined a well-defined data schema. Custom resources are registered with a `CustomResourceDefinition` (CRD) resource in the cluster.

An example for a CRD can be found in `manifests/crd.yml` ([Source](https://github.com/kubernetes/sample-controller/blob/master/artifacts/examples/crd.yaml)), which registers a new resource type named `Foo`.

When applying this resource to the cluster:

```bash
kubectl apply -f manifests/crd.yml
```

the CRD will now register the resource type at the cluster API. We can explain the resource using `kubectl explain`, and view the resource with `get crd`:

```bash
kubectl explain Foo
kubectl get crd foos.samplecontroller.k8s.io
```

<details>
<summary>Expected Output</summary>

```text
GROUP:      samplecontroller.k8s.io
KIND:       Foo
VERSION:    v1alpha1

DESCRIPTION:
    <empty>
FIELDS:
  apiVersion    <string>
    APIVersion defines the versioned schema of this representation of an object.
    Servers should convert recognized schemas to the latest internal value, and
    may reject unrecognized values. More info:
    https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources

  kind  <string>
    Kind is a string value representing the REST resource this object
    represents. Servers may infer this from the endpoint the client submits
    requests to. Cannot be updated. In CamelCase. More info:
    https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds

  metadata      <ObjectMeta>
    Standard object's metadata. More info:
    https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#metadata

  spec  <Object>
    <no description>

  status        <Object>
    <no description>
```

**Note**: the API server takes some time to register the resource after applying. If `kubectl explain Foo` fails immediately after creating the CRD with the error `error: couldn't find resource for "samplecontroller.k8s.io/v1alpha1, Resource=foos"`, wait a few seconds and try again.
</details>

We can also create new objects of this resource type:

```bash
kubectl apply -f manifests/foo_example.yml
kubectl get foo
kubectl describe foo
```

<details>
<summary>Expected Output</summary>

```text
foo.samplecontroller.k8s.io/example-foo created


NAME          AGE
example-foo   9s


Name:         example-foo
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  samplecontroller.k8s.io/v1alpha1
Kind:         Foo
Metadata:
  Creation Timestamp:  2026-07-24T21:04:24Z
  Generation:          1
  Resource Version:    128950
  UID:                 f7fd8666-186f-4834-a67f-99f5e0ceaeb9
Spec:
  Deployment Name:  example-foo
  Replicas:         1
Events:             <none>
```
</details>

This custom resource in itself can already be useful: we can create objects of this resource type, manage access to the resource using RBAC permissions, and store and query data in a structured way. Additionally, the data is stored in `etcd`. In other words, using this custom resource, we can make use of the infrastructure that Kubernetes provides us.

### Cleanup

Delete the `Foo` resource for the next step:

```bash
kubectl delete foo example-foo
```

## Custom Controllers

A controller is a piece of software which watches the cluster state and events, and reacts accordingly. In the introduction we learned about the `kube-controller-manager`, which implements the behavior for the standard resources. This includes e.g. the creation of a new Pod after a `Deployment` was scaled.

A custom controller extends the behavior of Kubernetes by reacting to events associated with standard resources, or by implementing custom behavior for custom resource types. We will take a look at the `sample-controller` example. But first, we must build the Go-binary for the controller itself:

```bash
sudo apt install golang
go version
```

<details>
<summary>Expected Output</summary>

```text
go version go1.26.5 linux/amd64
```
</details>

```bash
git clone https://github.com/kubernetes/sample-controller
cd ~/sample-controller
go build -o sample-controller .
```

After the build completes, you should have a `sample-controller` binary in the folder:

```bash
file sample-controller
```

<details>
<summary>Expected Output</summary>

```text
sample-controller: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, Go BuildID=OsOO7NVuEA16ASy0HpGh/0PYzVw8L-iGfro5I6Gea/enHGX8dbYxUKmkFoaSf5/9s7316DO-D02BbGIOhxw, BuildID[sha1]=efc935a10bfe01e36a5e4239ff7cc58b85a05a02, with debug_info, not stripped
```
</details>

We will now run the controller in the terminal, using our kubeconfig. Normally, the controller would run as a Pod within the cluster, with an associated `ServiceAccount` that grants it the required permissions to read/write e.g. `Foo` objects.

Start the controller in the terminal:

```bash
./sample-controller -kubeconfig=$HOME/.kube/k3s.yaml
```

<details>
<summary>Expected Output</summary>

```text
I0724 21:14:04.525481 1029769 controller.go:126] "Setting up event handlers"
I0724 21:14:04.525557 1029769 controller.go:168] "Starting Foo controller"
I0724 21:14:04.525565 1029769 controller.go:171] "Waiting for informer caches to sync"
I0724 21:14:04.625866 1029769 controller.go:177] "Starting workers" count=2
I0724 21:14:04.625887 1029769 controller.go:183] "Started workers"
```
</details>

If we now re-create the `example-foo` resource in a second terminal:

```bash
kubectl apply -f manifests/foo_example.yml
```

We can see activity in the logs of the controller:

```
I0724 21:16:01.004734 1029769 controller.go:222] "Successfully synced" objectName="default/example-foo"
I0724 21:16:01.004909 1029769 event.go:395] "Event occurred" object="default/example-foo" fieldPath="" kind="Foo" apiVersion="samplecontroller.k8s.io/v1alpha1" type="Normal" reason="Synced" message="Foo synced successfully"
```

The controller implements the behavior to sync a `Deployment` based on paramters given in the `Foo` resource. In the `example-foo` manifest, we have specified a `deploymentName: example-foo`. After we created the resource, the controller was notified that a new `Foo` resource was created. Based on this information, it created a new `Deployment` with the specified name and replicas. This `Deployment` in turn created a new Pod:

```bash
kubectl get pods,deployments
```

<details>
<summary>Expected Output</summary>

```text
NAME                               READY   STATUS    RESTARTS   AGE
pod/example-foo-687c486766-wkw4f   1/1     Running   0          2m1s

NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/example-foo   1/1     1            1           2m1s
```
</details>

At the same time, the controller has updated the status of the `Foo` resource to state that 1 replica is available:

```bash
kubectl describe foo example-foo
```

<details>
<summary>Expected Output (Shortened)</summary>

```text
Name:         example-foo
API Version:  samplecontroller.k8s.io/v1alpha1
Kind:         Foo
Spec:
  Deployment Name:  example-foo
  Replicas:         1
Status:
  Available Replicas:  1
Events:
  Type    Reason  Age                   From               Message
  ----    ------  ----                  ----               -------
  Normal  Synced  17s (x15 over 3m50s)  sample-controller  Foo synced successfully
```
</details>

If we patch the `example-foo` resource and increase the number of replicas, we can see that the `Deployment` is scaled as well:

```bash
kubectl patch foo example-foo --type merge -p '{"spec":{"replicas":3}}'
kubectl get deployment example-foo
```

<details>
<summary>Expected Output (Shortened)</summary>

```text
foo.samplecontroller.k8s.io/example-foo patched

NAME          READY   UP-TO-DATE   AVAILABLE   AGE
example-foo   3/3     3            3           7s
```
</details>

If we delete the `example-foo` resource, the `Deployment` and the Pods are deleted as well:

```bash
kubectl delete foo example-foo
kubectl get pods,deployments
```

<details>
<summary>Expected Output</summary>

```text
No resources found in default namespace.
```
</details>

While simple, this example highlights how powerful the combination of of custom resources and custom controllers can be. Exactly for this reason, the operator-pattern is very popular in Kubernetes. In the next chapter, we will take a look at an example for an operator.

## Cleanup

Terminate the controller process with `Ctrl+C` in the terminal, then:

```bash
kubectl delete crd foos.samplecontroller.k8s.io
```

```bash
bash cleanup.sh
```

Continue with [Operators](11-operators.md).
