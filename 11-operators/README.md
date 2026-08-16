# Operators

In this chapter we will investigate the concept of operators. In the previous chapter, we learned about custom resource types and custom controllers. Operators take these concepts a step further, and bundle multiple custom resources and custom controllers. They implement application-specific knowledge, and can fulfill powerful administrative tasks in a cluster. There are countless operators, which can be discovered on e.g. [operatorhub.io](https://operatorhub.io/).

In this chapter we will use the PostgreSQL-Operator [CloudNativePG](https://cloudnative-pg.io/) as an example. This chapter was inspired by [lukasfriedhoff/selfhosting-kubernetes](https://github.com/lukasfriedhoff/selfhosting-kubernetes).

## Install CloudNativePG Operator

An operator is installed like any other resource using a resource manifest. The operator itself ist a bundle of multiple resources, including the `CustomResourceDefinitions` and Pods required to implement the controllers.

```bash
kubectl apply --server-side -f https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v1.30.0/cnpg-1.30.0.yaml
kubectl rollout status deployment/cnpg-controller-manager -n cnpg-system --timeout=120s
```

After the `Deployment` finished its rollout, take a look at the custom resource types that were created:

```bash
kubectl get crds -o name | grep postgresql.cnpg.io
```

The `Cluster` resource type is very interesting, hence we will take a closer look in the next step.

## Creating a Database with the Operator

Using the `Cluster` resource, we can ask the operator to create a new PostgreSQL cluster for us. The creation of the database is fully automated by the operator:

```bash
kubectl apply -f manifests/postgres_cluster.yml
kubectl get cluster pg -w
```

<details>
<summary>Expected Output</summary>

```text
NAME   AGE   INSTANCES   READY   STATUS               PRIMARY
pg     2s    1                   Setting up primary   
pg     18s   1                   Setting up primary   
pg     18s   1                   Setting up primary   
pg     18s   1                   Waiting for the instances to become active   
pg     19s   1                   Waiting for the instances to become active   
pg     20s   1                   Waiting for the instances to become active   pg-1
pg     20s   1                   Waiting for the instances to become active   pg-1
pg     21s   1                   Waiting for the instances to become active   pg-1
pg     29s   1           1       Waiting for the instances to become active   pg-1
pg     29s   1           1       Creating a new replica                       pg-1
pg     29s   2           1       Creating a new replica                       pg-1
pg     39s   2           1       Creating a new replica                       pg-1
pg     39s   2           1       Creating a new replica                       pg-1
pg     39s   2           1       Waiting for the instances to become active   pg-1
pg     40s   2           1       Waiting for the instances to become active   pg-1
pg     42s   2           1       Waiting for the instances to become active   pg-1
pg     50s   2           2       Waiting for the instances to become active   pg-1
pg     50s   2           2       Creating a new replica                       pg-1
pg     50s   3           2       Creating a new replica                       pg-1
pg     59s   3           2       Creating a new replica                       pg-1
pg     59s   3           2       Creating a new replica                       pg-1
pg     59s   3           2       Waiting for the instances to become active   pg-1
pg     61s   3           2       Waiting for the instances to become active   pg-1
pg     62s   3           2       Waiting for the instances to become active   pg-1
pg     70s   3           3       Waiting for the instances to become active   pg-1
pg     70s   3           3       Cluster in healthy state                     pg-1
pg     70s   3           3       Cluster in healthy state                     pg-1
```
</details>

Here we can watch how the operator initially creates the primary of the database, waits until it is healthy, and then creates and joins additional replicas to the primary. Finally, the operator ensures the cluster is healthy.

From this single `Cluster` resource, the operator has created multiple `Pods`, `PersistentVolumeClaims`, `Services` and `Secrets`: 

```bash
kubectl get pods,pvc,services,secrets
```
<details>
<summary>Expected Output</summary>

```text
NAME       READY   STATUS    RESTARTS   AGE
pod/pg-1   1/1     Running   0          111s
pod/pg-2   1/1     Running   0          90s
pod/pg-3   1/1     Running   0          70s

NAME                         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/pg-1   Bound    pvc-74617146-3ada-470c-88d7-c5103c225953   1Gi        RWO            local-path     <unset>                 2m9s
persistentvolumeclaim/pg-2   Bound    pvc-b5861b9e-3e95-4e0c-bb79-060361b0a9e1   1Gi        RWO            local-path     <unset>                 100s
persistentvolumeclaim/pg-3   Bound    pvc-a0c07aff-21d2-4d79-b300-5b2a2f563782   1Gi        RWO            local-path     <unset>                 79s

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/kubernetes   ClusterIP   172.16.64.1     <none>        443/TCP    11h
service/pg-r         ClusterIP   172.16.121.47   <none>        5432/TCP   2m9s
service/pg-ro        ClusterIP   172.16.89.215   <none>        5432/TCP   2m9s
service/pg-rw        ClusterIP   172.16.115.33   <none>        5432/TCP   2m9s

NAME                    TYPE                       DATA   AGE
secret/pg-app           kubernetes.io/basic-auth   11     2m9s
secret/pg-ca            Opaque                     2      2m9s
secret/pg-replication   kubernetes.io/tls          2      2m9s
secret/pg-server        kubernetes.io/tls          2      2m9s
```
</details>

## Querying the Database

To test if the database works we dump the database version:

```bash
# Extract database password
PGPASS=$(kubectl get secret pg-app -o jsonpath='{.data.password}' | base64 -d)

# Send query on one of the postgres pods
kubectl exec pg-1 -c postgres -- env PGPASSWORD="$PGPASS" psql -h localhost -U app -d app -c "SELECT version();"
```

<details>
<summary>Expected Output</summary>

```text
                                                        version                                                        
----------------------------------------------------------------------------------------------------------------------
  PostgreSQL 16.14 (Debian 16.14-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)
```
</details>

We can also create a table in the database and insert some rows:

```bash
kubectl exec pg-1 -c postgres -- env PGPASSWORD="$PGPASS" psql -h localhost -U app -d app -c "
CREATE TABLE testing (id serial PRIMARY KEY, note text);
INSERT INTO testing (note) VALUES ('hello from postgres 16');
SELECT * FROM testing;
"
```

<details>
<summary>Expected Output</summary>

```text
CREATE TABLE
INSERT 0 1
  id |          note          
----+------------------------
  1 | hello from postgres 16
(1 row)
```
</details>

## Database Major Version Upgrade

We have already seen that the operator can automatically setup a database for us. Because it implements application-specific knowledge, it can also run complex operations on existing databases, for example a major version upgrade of the database.

For example, if we want to perform a major version upgrade of the database from Postgres 16 to version 18, all we have to do is to update the container image value in the resource:

```bash
kubectl patch cluster pg --type merge -p '{"spec":{"imageName":"ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie"}}'
kubectl get pods -w
```

The operator gets notified that the resource changed, compares the old to the new version, and realizes the major version has changed. It then creates a new `Job` (`pg-1-major-upgrade`), which runs `pg_upgrade`.

<details>
<summary>Expected Output</summary>

```text
cluster.postgresql.cnpg.io/pg patched

NAME                       READY   STATUS     RESTARTS   AGE
pg-1-major-upgrade-ppnz8   0/1     Init:1/2   0          1s
pg-1-major-upgrade-ppnz8   0/1     PodInitializing   0          2s
pg-1-major-upgrade-ppnz8   1/1     Running           0          2s
pg-1-major-upgrade-ppnz8   0/1     Completed         0          31s
pg-1-major-upgrade-ppnz8   0/1     Completed         0          32s
pg-1-major-upgrade-ppnz8   0/1     Completed         0          33s
pg-1-major-upgrade-ppnz8   0/1     Completed         0          33s
pg-1-major-upgrade-ppnz8   0/1     Completed         0          33s
pg-1                       0/1     Pending           0          0s
pg-1                       0/1     Pending           0          0s
pg-1                       0/1     Init:0/1          0          0s
pg-1                       0/1     Init:0/1          0          1s
pg-1                       0/1     Init:0/1          0          1s
pg-1                       0/1     PodInitializing   0          2s
pg-1                       0/1     Running           0          2s
pg-1                       0/1     Running           0          4s
pg-1                       0/1     Running           0          11s
pg-1                       1/1     Running           0          11s
pg-2-join-bhtlr            0/1     Pending           0          0s
pg-2-join-bhtlr            0/1     Pending           0          0s
pg-2-join-bhtlr            0/1     Pending           0          3s
pg-2-join-bhtlr            0/1     Init:0/1          0          3s
pg-2-join-bhtlr            0/1     Init:0/1          0          3s
pg-2-join-bhtlr            0/1     Init:0/1          0          3s
pg-2-join-bhtlr            0/1     PodInitializing   0          4s
pg-2-join-bhtlr            1/1     Running           0          4s
pg-2-join-bhtlr            0/1     Completed         0          6s
pg-2-join-bhtlr            0/1     Completed         0          7s
pg-2-join-bhtlr            0/1     Completed         0          8s
pg-2                       0/1     Pending           0          0s
pg-2                       0/1     Pending           0          0s
pg-2                       0/1     Init:0/1          0          0s
pg-2                       0/1     Init:0/1          0          1s
pg-2                       0/1     Init:0/1          0          1s
pg-2                       0/1     PodInitializing   0          2s
pg-2                       0/1     Running           0          2s
pg-2                       0/1     Running           0          4s
pg-2                       0/1     Running           0          10s
pg-2                       1/1     Running           0          11s
pg-3-join-cgn72            0/1     Pending           0          0s
pg-3-join-cgn72            0/1     Pending           0          0s
pg-3-join-cgn72            0/1     Pending           0          3s
pg-3-join-cgn72            0/1     Init:0/1          0          3s
pg-3-join-cgn72            0/1     Init:0/1          0          3s
pg-3-join-cgn72            0/1     Init:0/1          0          3s
pg-3-join-cgn72            0/1     PodInitializing   0          5s
pg-3-join-cgn72            1/1     Running           0          5s
pg-3-join-cgn72            0/1     Completed         0          10s
pg-3-join-cgn72            0/1     Completed         0          11s
pg-3-join-cgn72            0/1     Completed         0          12s
pg-3                       0/1     Pending           0          0s
pg-3                       0/1     Pending           0          0s
pg-3                       0/1     Init:0/1          0          0s
pg-3                       0/1     Init:0/1          0          0s
pg-3                       0/1     Init:0/1          0          0s
pg-3                       0/1     PodInitializing   0          2s
pg-3                       0/1     Running           0          2s
pg-3                       0/1     Running           0          4s
pg-3                       0/1     Running           0          10s
pg-3                       1/1     Running           0          11s
pg-3-join-cgn72            0/1     Completed         0          23s
pg-2-join-bhtlr            0/1     Completed         0          42s
pg-2-join-bhtlr            0/1     Completed         0          42s
pg-3-join-cgn72            0/1     Completed         0          23s
```
</details>

```bash
kubectl wait --for=condition=Ready pod/pg-1 --timeout=120s
kubectl get cluster pg
kubectl exec pg-1 -c postgres -- env PGPASSWORD="$PGPASS" psql -h localhost -U app -d app -c "SELECT version();"
kubectl exec pg-1 -c postgres -- env PGPASSWORD="$PGPASS" psql -h localhost -U app -d app -c "SELECT * FROM testing;"
```

<details>
<summary>Expected Output</summary>

```text
pod/pg-1 condition met


NAME   AGE     INSTANCES   READY   STATUS                     PRIMARY
pg     5m34s   3           3       Cluster in healthy state   pg-1


                                                      version                                                       
--------------------------------------------------------------------------------------------------------------------
  PostgreSQL 18.4 (Debian 18.4-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)


  id |          note          
----+------------------------
  1 | hello from postgres 16
(1 row)
```

The database was upgraded to version 18, the previously inserted rows remain unchanged.
</details>

## Major Version Downgrade

The operator can also validate operations if they are possible. For example, if we want to perform a major version downgrade of the database, we get an error, since the resource validation fails:

```bash
kubectl patch cluster pg --type merge -p '{"spec":{"imageName":"ghcr.io/cloudnative-pg/postgresql:16-minimal-trixie"}}'
```

<details>
<summary>Expected Output</summary>

```text
The Cluster "pg" is invalid: spec.imageName: Invalid value: "16": can't downgrade from major 18 to 16
```

The request is immediately rejected, even before it is persisted in `etcd` and there could cause actual changes on the cluster. A downgrade is not possible.
</details>

## Cleanup

Only delete the cluster resource, we still need the operator:

```bash
kubectl delete -f manifests/postgres_cluster.yml
```
