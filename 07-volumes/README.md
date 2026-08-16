# Persistence and Volumes

We previously learned that Kubernetes splits compute from state. However, there are still stateful workloads like a database which need to persist state. For this, Kubernetes introduces persistent volumes, alongside multiple abstractions to go with it.

We already got to know one form of a volume: the nginx Pod with an init-container had a volume of the type `emptyDir`, which is a non-persistent, empty directory used to share state between containers. In the chapter about configmaps we also passed a `ConfigMap` as volume to a container.

These types of volumes use the same interface like a classic volume, but are not meant to be used to persist state. To do this, we will first take a look at how Kubernetes provisions storage and exposes it as resource. After, we will pass the storage to a Pod such that data can be persisted.

## Storage Classes

A `StorageClass` is the first abstraction that Kubernetes introduces. The storage class describes properties of the backing storage. For example, one class could be called `sync-write`, as it is backed by storage with high throughput for synchronous writes, e.g. for database applications. Alternatively, a storage class `replicated` could be used to indicate storage is replicated and highly available.

The storage class also describes functionalities that the underlying storage supports, such as volume expansion. Also, it specifies the storage provider that is used to provision underlying storage, and to make it available using the Container Storage Interface (CSI). Thanks to interfaces like the CSI, Kubernetes can be extended using custom storage providers, for example with the local `rancher.io/local-path` provisioner which we will use in this chapter, or the Longhorn provider, which provides replicated storage. 

### View Storage Class

To start, we will take a look at existing storage classes:

```bash
kubectl get storageclass
```

<details>
<summary>Expected Output</summary>

```text
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  6h1m
```
</details>

We can see the storage class `local-path`, which is provided by the `rancher.io/local-path` provisioner. The `Reclaim Policy` specifies what to do with data after the volume is deleted in Kubernetes. In this case, the data will be deleted. The `Volume Binding Mode` specifies when storage should be provisioned: as soon as the storage is allocated, or once its actually needed, i.e. when a Pod wants to use it. Volume expansion allows to enlarge a volume after its creation - depending on the underlying storage this is not always possible.

We can also create our own storage class:

```bash
kubectl apply -f manifests/storageclass_retain.yml
```

The new storage class uses the reclaim policy `Retain`, i.e. data will not be deleted after a volume is deleted in Kubernetes:

```bash
kubectl get storageclass
```

## Persistent Volume

Now that we know what a storage class is, we can create a volume specifying one. This is done iwth the `PersistentVolume` resource. A `PersistentVolume` is a storage resource in the cluster, which - similar to CPU and RAM resources - can be consumed by a Pod.

To start, we will manually create a `PersistentVolume`. Creating a volume manually is also called static provisioning - more details later:

```bash
kubectl apply -f manifests/pv_local_path.yml
```

We can now view the `PersistentVolume`:

```bash
kubectl get pv
```

Here we can see that the status is `Available`: the volume was prepared, and can be used by a Pod.

<details>
<summary>Expected Output</summary>

```text
NAME          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM     STORAGECLASS      VOLUMEATTRIBUTESCLASS   REASON   AGE
busybox-pv    512Mi      RWO            Retain           Available             local-path        <unset>                          3s
```

Because the volume was statically provisioned, the reclaim policy is overriden to `Retain`.
</details>

## Persistent Volume Claim

Now that we have a volume, we can create a Pod that uses the `PersistenVolume`. This is done in two steps.

Storage resources, i.e. a `PersistentVolume`, must be requested through a `PersistentVolumeClaim` resource. This claim describes the requirements for the needed storage, i.e. the size and the storage class and others. When creating a `PersistentVolumeClaim`, Kubernetes looks for an available `PersistentVolume` that matches the specified requirements. If no `PersistentVolume` is found, a new one is created automatically. This is called dynamic provisioning.

After a matching `PersistentVolume` is found or created, the storage is mounted on the Kubernetes node and passed to the Pod.

Let's look at this in practical terms. We have already created a `PersistentVolume`:

```bash
kubectl get pv
```

We now create a `PersistentVolumeClaim`, which matches our existing `PersistentVolume`:

```bash
kubectl apply -f manifests/pvc_local_path.yml
```

If we now view the `PersistentVolumeClaim`, we can see that its in the state `Pending`. This is due to the volume binding mode being `WaitForFirstConsumer`:

```bash
kubectl get pvc busybox-data
kubectl describe pvc busybox-data
```

<details>
<summary>Expected Output</summary>

```text
NAME           STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
busybox-data   Pending                                      local-path     <unset>                 19s


Name:          busybox-data
[...]
Events:
  Type    Reason                Age                From                         Message
  ----    ------                ----               ----                         -------
  Normal  WaitForFirstConsumer  15s (x2 over 28s)  persistentvolume-controller  waiting for first consumer to be created before binding
```
</details>

So Kubernetes waits until a Pod is started which uses the `PersistentVolumeClaim`. If we create such a Pod:

```bash
kubectl apply -f manifests/pod_pvc_local_path.yml
```

Now we can observe multiple things: the `PersistentVolumeClaim` is resolved and it's state changes to `Bound`, i.e. the `PersistentVolumeClaim` has found its matching `PersistentVolume`. The `PersistentVolume` storage is now mounted on the node, and is passed to the Pod and mounted in the container:

```bash
kubectl get pvc
```

<details>
<summary>Expected Output</summary>

```text
NAME           STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
busybox-data   Bound    busybox-pv   512Mi      RWO            local-path     <unset>                 2m15s
```
</details>

Similarily, the state of the `PersistentVolume` is also in the state `Bound`:

```bash
kubectl get pv
```

<details>
<summary>Expected Output</summary>

```text
NAME         CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
busybox-pv   512Mi      RWO            Retain           Bound    default/busybox-data   local-path     <unset>                          3m36s
```
</details>

If we now connect to the Pod we can write data into the volume by writing files into the mount path in the container:

```bash
kubectl exec -it busybox-persistent -- sh
busybox:~# echo "Hello World" > /usr/share/message.txt
```

If we now re-create the pod:

```bash
kubectl delete pod busybox-persistent
kubectl apply -f manifests/pod_pvc_local_path.yml
```

We can see that the file has been persisted:

```bash
kubectl exec -it busybox-persistent -- cat /usr/share/message.txt
```

Because we are using the `local-path` provisioner, which effectively mounts a directory on the Kubernetes node into the container, we can also inspect the file inside the volume at the path we specified when creating the `PersistentVolume`. 

However, this must be done on the node where the Pod was scheduled: since `local-path` is not replicated, the folder will only be created on the node where it is needed. The Kubernetes scheduler chooses one node where the Pod should run after it was created. Because the storage is local, it must also be co-located on this node. This is also the reason the `local-path` storage class uses the volume binding mode `WaitForFirstConsumer`: it cannot pre-allocate storage in advance, as the node must be known where the Pod will run i.e. where the storage is required. To find out on which node the Pod is running, run `kubectl get pods -o wide`. Then run this command in a shell on the node:

```bash
ls /var/lib/rancher/k3s/storage/busybox-pv
```

<details>
<summary>Expected Output</summary>

```text
message.txt
```
</details>

## Static vs. Dynamic Provisioning

In the previous example we manually created a `PersistentVolume`, which we later consumed using a `PersistentVolumeClaim`. As already mentioned, a manually created `PersistentVolume` is also called statically provisioned. The benefit of static provisioning is that we can choose hte name of the `PersistentVolume` in advance. This can be a benefit in some scenarios, as we will shortly see. Additionally, a statically provisioned `PersistentVolume` has the reclaim policy `Retain` by default.

With dynamic provisioning, we do not create a `PersistentVolume`, but only a `PersistentVolumeClaim`. Kubernetes then automatically creates a matching `PersistentVolume` with the required parameters. Lets investigate: first we create a `PersistentVolumeClaim`:

```bash
kubectl apply -f manifests/pvc_local_path_dynamic.yml
```

If we now view the `PersistentVolumes`, we can see that no `PersistentVolume` was created yet:

```bash
kubectl get pv
```

If we now create a Pod that uses the `PersistentVolumeClaim`:

```bash
kubectl apply -f manifests/pod_pvc_local_path_dynamic.yml
```

we can see that a new `PersistentVolume` was created:

```bash
kubectl get pv
```

<details>
<summary>Expected Output</summary>

```text
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM                          STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-435dabff-9e97-42d6-ad33-9118f2606fbd   512Mi      RWO            Delete           Bound      default/busybox-data-dynamic   local-path     <unset>                          6s
```
</details>

The name of the `PersistentVolume` was chosen randomly. Additionally, the reclaim policy is `Delete`, as specified in the storage class. We can also see that the `PersistentVolume` is being associated with the `PersistentVolumeClaim` called `busybox-data-dynamic`, and is in the state `Bound`, as the `PersistentVolumeClaim` is already using the `PersistentVolume`.

If we delete the Pod the `PersistentVolumeClaim` and `PersistentVolume` remain in the state `Bound`:

```bash
kubectl delete -f manifests/pod_pvc_local_path_dynamic.yml
kubectl get pvc
```

If we were to re-create the Pod, it would use the `PersistentVolumeClaim` and the associated `PersistentVolume` again. However, if we delete the `PersistentVolumeClaim`:

```bash
kubectl delete pvc busybox-data-dynamic
```

we can see that the dynamic `PersistentVolume` is also deleted:

```bash
kubectl get pv
```

<details>
<summary>Expected Output</summary>

```text
NAME         CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
busybox-pv   512Mi      RWO            Retain           Bound    default/busybox-data   local-path     <unset>                          8m12s
```

The dynamically provisioned `PersistentVolume` is gone. Only the statically provisioned `busybox-pv` remains, which is still bound to the `busybox-data` PVC.
</details>

So when should one use static provisioning, and when dynamic provisioning? 

A statically provisioned `PersistentVolume` has the benefit that the name can be chosen in advance. Let's assume a cluster is in a broken state and must be re-created. If static `PersistentVolumes` as above are used, the storage-path is known in advance, as it is hard-coded in the `PersistentVolume` manifest. We have seen this earlier when setting the path when creating the `PersistentVolume`. As long as the reclaim policy is set to `Retain`, the cluster can be re-created, including all of the `PersistentVolume` resources. Since the `PersistentVolumes` are effectively metadata for the storage provisioner, the `PersistentVolume` are created on the existing directory. This automatically "imports" the data of the old cluster. Note that this only works on single-node clusters, for multi-node clusters, volumes would have to be pinned to a node using a `nodeAffinity` property.

With dynamic `PersistentVolumes`, since the name is randomised, the path on the node would also be unknown, with destroys the mapping of existing data and the new `PersistentVolumes`. While this schema works for the `local-path` provisioner, it does not work for all storage providers, since other providers may organize underlying storage differently. Additionally, static provisioning is not necessarily scalable, since `PersistentVolumes` must always be created in advance by the administrator.

To backup a cluster using dynamically provisioned volumes, the entire cluster state, which includes all Kubernetes API objects, must be saved as a snapshot. Additionally, the contents of the volumes must bes backed up. Since the cluster state is saved, the mapping between `PersistentVolume` names and `PersistentVolumeClaims` is also retained. When restoring, the entire cluster state is restored, alongside the data in the volumes. One tool that uses this approach is [Velero](https://velero.io/).

To conclude, static provisioning only makes sense in a few scenarios. It can ease the operation of a cluster in some cases, but is not necessarily scalable or portable. Dynamic provisioning further increases the complexity, but remains flexible and scalable, and should be the preferred approach in most scenarios.

## Replicated Storage with Longhorn

As initially mentioned, the CSI allows us to integreate external storage providers. One very popular example is [Longhorn](https://longhorn.io/). Compared to the `local-path` provisioner, where the storage is local on a single node, Longhorn replicates storage between multiple K8s nodes, providing failure tolerance.

### Install Longhorn

Under the hood, Longhorn uses iSCSI. Hence, some tools need to be present on the Kubernetes nodes such that Longhorn can work properly. On Ubuntu the tools can be installed with:

```bash
sudo apt-get install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid
```

Longhorn can be installed by applying a resource manifest file, which bundles all required resources:

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.12.0/deploy/longhorn.yaml
```

<details>
<summary>Expected Output (Excerpt)</summary>

```text
customresourcedefinition.apiextensions.k8s.io/volumes.longhorn.io created
daemonset.apps/longhorn-manager created
deployment.apps/longhorn-driver-deployer created
deployment.apps/longhorn-ui created
```
</details>

It can take some time until all Pods have been properly started. Some Pod restarts may occur during the setup:

```bash
watch -n 1 kubectl get pods -n longhorn-system
```

<details>
<summary>Expected Output (after about 1-2 minutes)</summary>

```text
NAME                                 READY   STATUS    RESTARTS   AGE
csi-attacher-...                     1/1     Running   0          1m
csi-provisioner-...                  1/1     Running   0          1m
csi-resizer-...                      1/1     Running   0          1m
csi-snapshotter-...                  1/1     Running   0          1m
engine-image-ei-...                  1/1     Running   0          1m
instance-manager-...                 1/1     Running   0          1m
longhorn-csi-plugin-...              3/3     Running   0          1m
longhorn-driver-deployer-...         1/1     Running   0          2m
longhorn-manager-...                 2/2     Running   0          2m
longhorn-ui-...                      1/1     Running   0          2m
```
</details>

Longhorn automatically creates a new `StorageClass` that we can use:

```bash
kubectl get storageclass
```

<details>
<summary>Expected Output</summary>

```text
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
longhorn (default)     driver.longhorn.io      Delete          Immediate              true                   81s
longhorn-static        driver.longhorn.io      Delete          Immediate              true                   78s
```
</details>

**Warning**: Longhorn marks its storage class automatically as default! The default storage class is determined by a `is-default-class` annotation. If multiple are present, Kubernetes uses the most recently created storage class. To prevent confusion and errors, remove annotation from the `longhorn` storage class:

```bash
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

### Accessing the Web-UI

Longhorn ships with a Web-UI which we can use to view provisioned volume and manage settings:

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8081:80
```

In the Web-UI, we can see that there are currently no Longhorn volumes present. Longhorn shows us the amount of available storage, which in most cases should be the size and remaining space on the OS-disk. We can also see that Longhorn is active on all nodes, and pools the storage together.

### Using Longhorn Storage

To use Longhorn-backed storage, we create a `PersistentVolumeClaim` which uses the `longhorn` storage class:

```bash
kubectl apply -f manifests/pvc_longhorn.yml
kubectl get pvc busybox-data-longhorn
```

As soon as the `PersistentVolumeClaim` has been created, we can see that a new `PersistentVolume` was created, since the `longhorn` storage class uses the volume binding mode `Immediate`:

```bash
kubectl get pv
```

<details>
<summary>Expected Output</summary>

```text
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                           STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-9eccb4b6-0697-4286-9f51-775bb9e5296d   1Gi        RWO            Delete           Bound    default/busybox-data-longhorn   longhorn       <unset>                          68s
```
</details>

We can now create a Pod that uses the volume:

```bash
kubectl apply -f manifests/pod_pvc_longhorn.yml
```

As soon as the Pod is created, we can see in the Longhorn Web-UI that the volume is being "attached". This means that the storage is made available as an iSCSI block device on the K8s node. Afterwards, the storage is passed to the Pod and mounted in the container.

The node the volume is attached to depends on the placement of the Pod, and thus the scheduler. The scheduler does consider only nodes where storage can be mounted, to prevent that a node is selected that cannot provide the required storage to the Pod. In the case of local storage, like the `local-path` provisioner, the number of possible nodes is reduced if the volume already exists on a node. With Longhorn, all nodes running Longhorn are possible, since Longhorn can also stream data between nodes if data is not physically present on a node, or if a node does not have an underlying storage device.

### Longhorn Backups

Longhorn does support volume snapshots, and can perform automated volume backups to an external S3 endpoint. When re-creating a cluster, volume data can be restored. Longhorn also backs up the associated `PersistentVolume` and `PersistentVolumeClaim`, which can be re-created after restoring the data from S3. An in-detail explaination is omitted at this point.

## Cleanup

```bash
bash cleanup.sh
```

Continue with [Workloads](08-workloads.md).
