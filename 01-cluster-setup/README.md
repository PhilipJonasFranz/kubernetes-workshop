# Cluster Setup

In this chapter we will setup our Kubernetes cluster using K3s, and learn the basics to interact with the cluster.

## Cluster Setup

To begin, open SSH sessions into each of your three nodes. To create the first K3s Node and initialize the cluster, you must first choose a random token. This token will be required to join subsequent nodes to the cluster, so ensure to write it down. 

On the first node, run the setup script with the token:

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=<CHANGE_ME> sh -s - server \
    --cluster-init \
    --cluster-cidr=172.16.0.0/18 \
    --service-cidr=172.16.64.0/18 \
    --cluster-dns=172.16.64.10 \
    --disable=traefik \
    --disable=servicelb
```

The `--cluster-cidr` is the subnet from which Pod IP-addresses will be taken from. Analogous is the `--service-cidr` the subnet for services. `--cluster-dns` sets a static IP for the CoreDNS service running within Kubernetes, which is used to resolve cluster-internal DNS names.

<details>
<summary>Expected Output</summary>

```text
[INFO]  Finding release for channel stable
[INFO]  Using v1.36.2+k3s1 as release
[INFO]  Downloading hash https://github.com/k3s-io/k3s/releases/download/v1.36.2%2Bk3s1/sha256sum-amd64.txt
[INFO]  Downloading binary https://github.com/k3s-io/k3s/releases/download/v1.36.2%2Bk3s1/k3s
[INFO]  Verifying binary download
[INFO]  Installing k3s to /usr/local/bin/k3s
[INFO]  Skipping installation of SELinux RPM
[INFO]  Creating /usr/local/bin/kubectl symlink to k3s
[INFO]  Creating /usr/local/bin/crictl symlink to k3s
[INFO]  Creating /usr/local/bin/ctr symlink to k3s
[INFO]  Creating killall script /usr/local/bin/k3s-killall.sh
[INFO]  Creating uninstall script /usr/local/bin/k3s-uninstall.sh
[INFO]  env: Creating environment file /etc/systemd/system/k3s.service.env
[INFO]  systemd: Creating service file /etc/systemd/system/k3s.service
[INFO]  systemd: Enabling k3s unit
Created symlink /etc/systemd/system/multi-user.target.wants/k3s.service → /etc/systemd/system/k3s.service.
[INFO]  systemd: Starting k3s
```
</details>

To setup and join the other nodes to the cluster, the command looks similar, however, the `--cluster-init` flag is replaced with `--server https://<IP of first server>:6443`. This instructs the setup script to join an existing cluster, rather than to initialize a new one. This requires the token chosen earlier to authenticate at the existing node.

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=<CHANGE_ME> sh -s - server \
    --server https://<IP of first server>:6443 \
    --cluster-cidr=172.16.0.0/18 \
    --service-cidr=172.16.64.0/18 \
    --cluster-dns=172.16.64.10 \
    --disable=traefik \
    --disable=servicelb
```

That's it! The cluster _should_ now be ready. A small sanity check:

```bash
sudo systemctl is-active k3s
```

<details>
<summary>Expected Output</summary>

```text
active
```
</details>

## Getting the kubeconfig

To access a cluster we need a kubeconfig. For our cluster, this config is generated at `/etc/rancher/k3s/k3s.yaml`. Copy it into your home directory either on the node or to your host and change the permissions:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/k3s.yaml
sudo chown $USER:$USER ~/.kube/k3s.yaml
export KUBECONFIG=~/.kube/k3s.yaml
```

**Note**: When copying the kubeconfig to your host, ensure to change IP address of the `server: https://127.0.0.1:6443` entry to one of the K3s node IPs.

Lets take a look into the kubeconfig:

```bash
cat $KUBECONFIG
```

<details>
<summary>Expected Output (Sorted)</summary>

```yaml
apiVersion: v1
kind: Config

clusters:
- cluster:
    certificate-authority-data: LS0tLS1CR [...] EUtLS0tLQo=
    server: https://127.0.0.1:6443
  name: default

users:
- name: default
  user:
    client-certificate-data: LS0tLS1CRU [...] LS0tLS0K
    client-key-data: LS0tLS1CRUdJ [...] LRVktLS0tLQo=

contexts:
- context:
    cluster: default
    namespace: default
    user: default
  name: default

current-context: default
```
</details>

The kubeconfig is composed of three sections: `clusters`, `users` and `contexts`:

- `clusters` stores one entry per cluster. This includes the name of the cluster, the address to connect to it and a certificate to check the authenticity of the server
- `users` stores one entry per user, including a name, certificate and private key
- `contexts` maps user entries to clusters and defines the standard namespace to use when interacting with the cluster with kubectl

Kubernetes uses automatic mutual TLS (mTLS) for all communication between control-plane components and interactions with the cluster API by users, i.e. us. The certificates in the kubeconfig are used to secure the channel between the administrator and the API-server. Alternative authentication types such as tokens are also supported.

## kubectl

To interact with the cluster-API, the CLI-tool `kubectl` is typically used. Follow the instructions in the [documentation](https://kubernetes.io/docs/tasks/tools/) to install it. Other interaction types such as REST are also possible. `kubectl` needs a kubeconfig to authenticate with a cluster. One way to pass the config file is by setting the `KUBECONFIG` environment variable in the shell which points to the path of the `kubeconfig`. We already did this in the previous step. If `kubectl` is missing its kubeconfig, you will see errors like these:

```
E0731 07:44:34.077351 2990421 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
```

Kubectl is structurally similar to the CLI of Docker. The syntax is structured like this:

```bash
kubectl <verb> <parameter>
```

The verb describes the operation to do, e.g. `apply`, `delete`, `describe` or `explain`. You can also optionally install tab completions for `kubectl` to make it easier to navigate the tool. For example, for bash:

```bash
sudo apt-get install -y bash-completion
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
sudo chmod a+r /etc/bash_completion.d/kubectl
```

If you are using another shell, please follow the [documentation](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_completion/) for installation instructions.

A selection of the most relevant verbs for this workshop are listed below:

- `apply`: create a resource
- `delete`: delete a resource
- `get`: show an overview of selected resources
- `describe`: show details for a specific resource
- `explain`: show documentation for a resource or specific part of it
- `exec`: run a command within a container running in Kubernetes
- `port-forward`: port-forward a port of a Pod running in Kubernetes to the local machine

The following guides will state the required kubectl commands to follow the content.

## Check Cluster State

We will now contact the cluster. To start, we can show all nodes that are part of the cluster, and all services that are part of the standard installation. If no nodes are displayed, it can take some time for nodes to initialize and join the cluster, depending on the hardware up to one or more minutes.

```bash
kubectl get nodes
kubectl get pods -A
```

<details>
<summary>Expected Output</summary>

The kubectl commands use the `get` verb to show an overview of all resources of types `Node` and `Pod`. Notice the pluralized name of the resource type: kubectl is fairly flexible regarding resource names: `kubectl` get node` and `kubectl get no` both work as well and result in the same output.

```text
NAME         STATUS   ROLES                AGE   VERSION
k3s-ubuntu   Ready    control-plane,etcd   49s   v1.36.2+k3s1

kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   coredns-5f5694d56b-v8p55                  1/1     Running   0          61s
kube-system   local-path-provisioner-58d557dc48-56zvg   1/1     Running   0          61s
kube-system   metrics-server-7c86f97b8d-67zrh           1/1     Running   0          61s
```
</details>

You should see three entries: `coredns`, the cluster-internal DNS server for which we set the IP address previously, the `local-path-provisioner`, which is responsible to provision storage resources on the nodes, and the `metrics-server` for telemetry.

## Graphical UIs for Administration

I recommend using a GUI to manage a cluster, as they can help to get an overview of everything thats happening within a cluster. In this workshop we will use many `kubectl` commands, but some operations like container logs, container shells and port-forwardings can be conveniently done in GUIs.

I recommend two tools:

### Freelens

Freelens is a native desktop-client for macOS, Linux and Windows. Installation instructions can be found in the [GitHub Repository](https://github.com/freelensapp/freelens).

To add the cluster in Freelens, navigate to `File > Add Cluster`. Here you can paste your kubeconfig. **Important**: change the IP address of the server from `127.0.0.1` to one of the Node IPs.

### Kite

Kite is a browser-based management UI with a similar structure to Freelens. Kite can either be run within the cluster itself, or as external Docker container.

**In Cluster**:

```bash
kubectl apply -f manifests/kite_install.yml
```

After the installation, Kite is available at `http://<node ip>:30000`.

**Docker Container**

```bash
docker run --rm -p 8080:8080 ghcr.io/zxh326/kite:latest
```

Afterwards, Kite will be available at `http://localhost:8080`.

**Configuring Kite**

After the installation, the cluster must be added. If Kite is running within the cluster, you can select the option `In-Cluster` after creating the admin user. Alternatively you can pass in the kubeconfig File. Again, pay attention to change the cluster API endpoint from `127.0.0.1` to one of the node IPs where the API will be reachable.

## Uninstalling K3s

If something goes wrong, K3s can be easily uninstalled using an uninstaller:

```bash
/usr/local/bin/k3s-uninstall.sh
```

This script must be run on all nodes. Afterwards, you can run the installation script again to set up the cluster again.

## Resource Manifestsa

Kubernetes specifies objects using resource manifests. These are typically written in `.yaml` files. A resource always has an API version and a type, which is specified as `kind`. The resource type defines how the resource definition must look like, as the structure of the resources are pre-defined and validated before creating them:

```yaml
kind: ServiceAccount
apiVersion: v1
metadata:
  name: kite
  namespace: kube-system
```

To get quick information about a specific resource, you can use kubectl and the `explain` verb to get documentation details:

```bash
kubectl explain <resource path>
```

For example, to get information about the `namespace` field in the above manifest, you can use this command:

```bash
kubectl explain serviceaccount.metadata.namespace
```

In the command, `serviceaccount` is the name of the resource type, i.e. the `kind` field. The remainder of the path is the `yaml`-Path within the resource.

For this workshop, we will primarily get to know the built-in resource types. Manifests can be intimidating when starting out, as it is unclear which fields exist and what they do. A more complete documentation can be found [here](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.36/).

## Next Steps

In the following chapters we will create objects in the cluster by applying resource manifests. To wipe the cluster clean after each chapter, you can use the cleanup script included in this repository:

```bash
bash cleanup.sh
```

The script empties the `default`-namespace, and deletes all other non-essential namespaces. Kite will not be removed.

Let's start our journey with [Namespaces](02-namespaces.md).
