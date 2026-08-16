# ConfigMaps & Secrets

Containers frequently need a configuration, environment variables or credentials. In Docker, these information are commonly passed via volume mounts or as environment variables. A similar concept exists in Kubernetes.

## ConfigMap

A `ConfigMap` is a resource which stores key-value pairs. A `ConfigMap` can be used as a source for environment variables, but can also store entire configuration files as values. This can even include binary files! The resource is stored in the `etcd` database, and can thus be accessed from anywhere within the cluster. This removes the need to manage configuration files, as we dont have to ensure the file is present on the node the workload is running on.

### Create a ConfigMap

```bash
kubectl apply -f manifests/configmaps.yml
```

The manifest creates two `ConfigMap` resources: `busybox-env` with individual key-value pairs which we will use as environment variables, and `web-index`, which stores an entire `index.html` file.

If we inspect a `ConfigMap` we can view some additional metadata, alongside the encoded key-value pairs in the `data` field:

```bash
kubectl get configmap busybox-env -o yaml
kubectl get configmap web-index -o yaml
```

<details>
<summary>Expected Output (Excerpt)</summary>

```text
data:
  greeting: Hello from the ConfigMap
  index.html: |
    <h1>Hello from ConfigMap</h1>
kind: ConfigMap
```
</details>

### Passing a ConfigMap to a Pod

#### Keys as Files

What can we now do with a `ConfigMap`? One option is to pass the files in a `ConfigMap` as config files to a Pod. The manifest `pod_config_volume.yml` creates a nginx-Pod, which uses the `ConfigMap` called `web-index` as volume. Additionally, a `ClusterIP` service `web` is also created:

```bash
kubectl apply -f manifests/pod_config_volume.yml
```

If we now send a request to the service `web`:

```bash
kubectl apply -f manifests/pod_debug_netshoot.yml
kubectl exec -it netshoot -- bash
netshoot:~# curl web
```

we get the content of the `ConfigMap` as `index.html`.

#### Keys as Environment Variables

We can also pass the key-value pairs of the `ConfigMap` as environment variables to a Pod. For this, we create a busybox Pod which receives its environment from the `busybox-env` configmap. We can then print out the values of the variables from within the busybox container:

```bash
kubectl apply -f manifests/pod_config_env.yml
kubectl exec -it busybox -- sh
busybox:~# echo $greeting
busybox:~# echo $some_value
```

<details>
<summary>Expected Output (Excerpt)</summary>

```text
Hallo aus der ConfigMap
This is another value
```
</details>

## Secrets

Next to generic configuration files, credentials are frequently needed as well. One way to pass them could be through a `ConfigMap`. However, Kubernetes offers a separate resource type which should be used for sensitive informations: the `Secret`. Conceptually, a `ConfigMap` and a `Secret` are very similar. However, the main benefit is that the `Secret` is a distinct resource type, which introduces an explicit barrier when managing RBAC Access Control rules. We will take a look at RBAC in detail later.

Additionally, there are distinct formats for `Secret` resources, which implement frequently used credential types, such as credentials for Docker registries or TLS certificates. However, a generic secret type is also available for arbitrary data.

One important thing to note is that secrets are not encrypted by default. They are base64 encoded, which is to ensure compatibility, not security. Kubernetes optionally offers the functionality to [encrypt stored resources at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) in `etcd`, including `Secrets`.

### Creating a Secret

Let's create a secret:

```bash
kubectl apply -f manifests/secret.yml
```

### Inspecting a Secret

We can inspect the secret using:

```bash
kubectl get secret busybox-secret -o yaml
```

Note that while the secret is stored in base64, it is stored in plaintext in one of the annotations!

<details>
<summary>Expected Output (Excerpt)</summary>

```text
apiVersion: v1
data:
  API_TOKEN: czNjcjN0LXRva2Vu
kind: Secret
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"v1","kind":"Secret","metadata":{"annotations":{},"name":"busybox-secret","namespace":"default"},"stringData":{"API_TOKEN":"s3cr3t-token"},"type":"Opaque"}
  creationTimestamp: "2026-08-15T15:04:13Z"
  name: busybox-secret
  namespace: default
  resourceVersion: "8884077"
  uid: 77b5f91e-72ea-4960-84fb-f86ec9b16b1b
type: Opaque
```
</details>

To decode the actual value of the secret, we can simply pipe the base64 data into a CLI tool:

```bash
kubectl get secret busybox-secret -o jsonpath='{.data.API_TOKEN}' | base64 -d
```

<details>
<summary>Expected Output</summary>

```text
s3cr3t-token
```
</details>

### Environment Variables from Secret

Similar to a `ConfigMap`, we can pass a `Secret` as files or environment variables to a Pod:

```bash
kubectl apply -f manifests/pod_secret.yml
```

Inside the Pod we now find the API token once as file, and once stored inside an environment variable:

```bash
kubectl exec -it busybox-secret -- sh
busybox:~# cat /etc/secret/API_TOKEN
busybox:~# echo $API_TOKEN
```

## Cleanup

```bash
bash cleanup.sh
```

Continue with [Volumes](07-volumes.md).
