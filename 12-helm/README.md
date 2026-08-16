# Helm & Helm Charts

Until now, we have created resources for the most part ourselves, with the exception of controllers and operators doing that for us. We have created `ReplicaSets`, `Services` etc. manually, to gradually build up a larger infrastructure. But what about mode complex applications? Do we have to do everything ourselves?

The answer to that question is [Helm](https://helm.sh), the inofficial "Package Manager" of Kubernetes. So-called Helm Charts are collections of resource templates which can be rendered into valid resource manifest, and applied to a cluster with a single command. All possible configuration values for a Helm Chart are located in a single `.yaml` file. These values can change individual values inside a resource, and can even determine if a resource is created at all.

For this chapter, we will use the Helm Chart for [Nextcloud](https://github.com/nextcloud/helm/tree/main/charts/nextcloud). Many other Helm Charts can be found e.g. on [Artifacthub](https://artifacthub.io/).

## Installing Helm

To install the Helm CLI, follow the instructions on the [official Documentation](https://helm.sh/docs/intro/install). Afterwards, you should be able to run the Helm tool in your terminal:

```bash
helm version
```

<details>
<summary>Expected Output</summary>

```text
version.BuildInfo{Version:"v4.2.3", GitCommit:"43e8b7feece8beb0fcba47059ec9b522fd929a64", GitTreeState:"clean", GoVersion:"go1.26.5", KubeClientVersion:"v1.36"}
```
</details>

## Helm Repositories

Helm Charts are pulled out of Helm Repositories. Conceptually, you can think of them like a package- or container-registry. Before we can install a Helm Chart out of a repository, we must add it to Helm:

```bash
helm repo add nextcloud https://nextcloud.github.io/helm/
```

Helm itself works outside of Kubernetes, compared to controllers and operators. Effectively, Helm is a templating engine, which runs on a device outside of the cluster. If we want to install a Helm Chart, Helm renders the template based on the provided or default values into valid resource manifests, and uses our kubeconfig to apply the resources on the cluster. Additionally, Helm stores metadata about the release in a `Secret` resource. This allows Helm to manage the lifecycle of a installed Helm Chart, and to perform Rollbacks to a previous version of the release.

## Helm-Templating in Detail

Lets take a brief moment to look at how Helm templates are structured. For this, we will use the [database secret](https://github.com/nextcloud/helm/blob/main/charts/nextcloud/templates/db-secret.yaml) of the Nextcloud chart as example:

```yaml
{{- if or .Values.mariadb.enabled .Values.externalDatabase.enabled .Values.postgresql.enabled }}
{{- if not .Values.externalDatabase.existingSecret.enabled }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-db
  labels:
    {{- include "nextcloud.labels"  ( dict "rootContext" $ ) | nindent 4 }}
type: Opaque
data:
  {{- if .Values.mariadb.enabled }}
  {{- with .Values.mariadb.auth }}
  db-username: {{ .username | b64enc | quote }}
  db-password: {{ .password | b64enc | quote }}
  {{- end }}
  {{- else if .Values.postgresql.enabled }}
  {{- with .Values.postgresql.global.postgresql.auth }}
  db-username: {{ .username | b64enc | quote }}
  db-password: {{ .password | b64enc | quote }}
  {{- end }}
  {{- else }}
  {{- with .Values.externalDatabase }}
  db-username: {{ .user | b64enc | quote }}
  db-password: {{ .password | b64enc | quote }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end }}
```

Right at the start of the template, we can see an if-guard: specific requirements must be met such that this templates returns any content at all if it is rendered. In this case, database-options and no external database secret must be configured. Within the template, we can see that e.g. the name of the `Secret` resource is dynamically generated to prevent name collisions using `{{ .Release.Name }}-db`, where `.Release.Name` is the name or instance of the installed Helm Chart. A Helm Chart can be installed multiple times, the only difference must be the release name, i.e. the instance name of the installation.

For the values of the secret a base64 encoder function is used. Helm uses the [Go templating language](https://pkg.go.dev/text/template@go1.26.5), which is extended with the [sprig](https://masterminds.github.io/sprig/) library, which provides functions like `b64enc`.

## Install a Helm Chart

Let's start with the simple example: we install a Helm Chart without any additional configuration:

```bash
helm install my-release nextcloud/nextcloud
```

<details>
<summary>Expected Output</summary>

```text
NAME: my-release
LAST DEPLOYED: Mon Jul 27 21:34:02 2026
NAMESPACE: default
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
#######################################################################################################
## WARNING: You did not provide an external database host in your 'helm install' call                ##
## Running Nextcloud with the integrated sqlite database is not recommended for production instances ##
#######################################################################################################

For better performance etc. you have to configure nextcloud with a resolvable database
host. To configure nextcloud to use and external database host:


1. Complete your nextcloud deployment by running:

  export APP_HOST=127.0.0.1
  export APP_PASSWORD=$(kubectl get secret --namespace default my-release-nextcloud -o jsonpath="{.data.nextcloud-password}" | base64 --decode)

  ## PLEASE UPDATE THE EXTERNAL DATABASE CONNECTION PARAMETERS IN THE FOLLOWING COMMAND AS NEEDED ##

  helm upgrade my-release nextcloud/nextcloud \
    --set nextcloud.password=$APP_PASSWORD,nextcloud.host=$APP_HOST,service.type=ClusterIP,mariadb.enabled=false,externalDatabase.user=nextcloud,externalDatabase.database=nextcloud,externalDatabase.host=YOUR_EXTERNAL_DATABASE_HOST
```
</details>

After the installation, we get some useful hints about what to do next, e.g. how to ret rieve the admin password. Lets look at what resources have been created. For that, we can use labels to select resources based on the release name:

```bash
kubectl get all -l app.kubernetes.io/instance=my-release
```

<details>
<summary>Expected Output</summary>

```text
NAME                                        READY   STATUS    RESTARTS   AGE
pod/my-release-nextcloud-6d9bf84bb7-h9ftb   1/1     Running   0          24s

NAME                           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/my-release-nextcloud   ClusterIP   172.16.81.207   <none>        8080/TCP   24s

NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/my-release-nextcloud   1/1     1            1           24s

NAME                                              DESIRED   CURRENT   READY   AGE
replicaset.apps/my-release-nextcloud-6d9bf84bb7   1         1         1       24s
```
</details>

We can see that a simple `Deployment` and a `Service` was created. The `Service` is of type `ClusterIP`, and thus only reachable from within the cluster. We can port-forward the service to reach our Nextcloud instance:

```bash
kubectl port-forward service/my-release-nextcloud 8085:8080
```

You should get a login screen, or at least a warning about an untrusted domain, which we will fix later.

## Configuring a Helm Chart

Helm Charts use a configuration file called `values.yaml`. The file contains all possible configuration parameters, alongside their default values. The default values for the Nextcloud Helm Chart can be found [here](https://github.com/nextcloud/helm/blob/main/charts/nextcloud/values.yaml).

The configuration options listed in this file are all specific to this Helm Chart. There is no pre-defined structure for these files, so they can be quite complex to navigate. Within the Helm Chart, the values are retrieved during the templating process, influencing the result of the rendering process.

### Nextcloud with LoadBalancer

If we want to change the Nextcloud `Service` to type `LoadBalancer`, we can use the option `service.type` in the values (line 767 in the default values). Helm merges our custom configuration with the default values, so we only have to provide changed values. To start, we create our own `values.yaml`. Here, we can overwrite the values we want:

```yaml
service:
  type: LoadBalancer
```

Helm offers the option to do a dry-run, i.e. to only render and output the resulting manifests, not applying them. This way, we can inspect the resulting manifests with and without our custom values:

```bash
helm delete my-release
helm install my-release nextcloud/nextcloud -f manifests/values.yaml --dry-run > with_values.txt
helm install my-release nextcloud/nextcloud --dry-run > without_values.txt
diff with_values.txt without_values.txt
```

<details>
<summary>Expected Output</summary>

```text
2c2
< LAST DEPLOYED: Mon Jul 27 21:54:52 2026
---
> LAST DEPLOYED: Mon Jul 27 21:55:01 2026
42c42
<   type: LoadBalancer
---
>   type: ClusterIP
188,191c188
<   NOTE: It may take a few minutes for the LoadBalancer IP to be available.
<         Watch the status with: 'kubectl get svc --namespace default -w my-release-nextcloud'
< 
<   export APP_HOST=$(kubectl get svc --namespace default my-release-nextcloud --template "{{ range (index .status.loadBalancer.ingress 0) }}{{ . }}{{ end }}")
---
>   export APP_HOST=127.0.0.1
197c194
<     --set nextcloud.password=$APP_PASSWORD,nextcloud.host=$APP_HOST,service.type=LoadBalancer,mariadb.enabled=false,externalDatabase.user=nextcloud,externalDatabase.database=nextcloud,externalDatabase.host=YOUR_EXTERNAL_DATABASE_HOST
---
>     --set nextcloud.password=$APP_PASSWORD,nextcloud.host=$APP_HOST,service.type=ClusterIP,mariadb.enabled=false,externalDatabase.user=nextcloud,externalDatabase.database=nextcloud,externalDatabase.host=YOUR_EXTERNAL_DATABASE_HOST
```
</details>

Comparing the two we can see that indeed, the `Service` type was changed to `LoadBalancer`. If we now install the Helm Chart with the custom values:

```bash
helm install my-release nextcloud/nextcloud -f manifests/values.yaml
```

And view the created `Service`:

```bash
kubectl get svc
```

we can see that the `Service` for Nextcloud now has a load-balancer IP address:

<details>
<summary>Expected Output</summary>

```text
NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
kubernetes             ClusterIP      172.16.64.1      <none>        443/TCP          2d8h
my-release-nextcloud   LoadBalancer   172.16.114.212   10.24.1.20    8080:31513/TCP   33s
```
</details>

If we now open Nextcloud in a browser we will get an error:

```
Access through untrusted domain
Please contact your administrator. If you are an administrator, edit the "trusted_domains" setting in config/config.php like the example in config.sample.php. 
```

Luckily, the Helm Chart offers us configuration options to pre-configure the trusted domains for Nextcloud: in the default values, we can find the option `nextcloud.trustedDomains`. Here we can add the load-balancer IP address. However, we must also change another thing: we must ensure the Nextcloud `Service` always receives the same `LoadBalancer` IP address, otherwise the assignment is not guaranteed, and depends of the order of creation of services. For this, we can change the option `service.loadBalancerIP`.

The new values are located in `values_trusted_domain.yaml`.

## Helm Chart Upgrade

An already existing Helm Chart can be upgraded with new values in-place:

```bash
helm upgrade my-release nextcloud/nextcloud -f manifests/values_trusted_domain.yaml
```

Helm updates only the changed resources. For example, the existing `Service` remains unchanged, while the Pod gets re-created since it's configuration changed:

```bash
NAME                                        READY   STATUS    RESTARTS   AGE
pod/my-release-nextcloud-747c5855f7-5fhvp   1/1     Running   0          5s

NAME                           TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/my-release-nextcloud   LoadBalancer   172.16.123.48   10.24.1.21    8080:31372/TCP   5m10s
```

Now we can reach Nextcloud normally at `http://<loadbalancer-ip>:8080` and get a login screen.

### Nextcloud with Persistence

Another example how we can configure Nextcloud is by adding persistent Storage: by default, Nextcloud does not use a persistent volume for our data:

```bash
kubectl get pvc
```

<details>
<summary>Expected Output</summary>

```text
No resources found in default namespace.
```
</details>

In the default values of the Helm Chart, we can find the key `persistence`. Here, we can enable the usage of a `PersistentVolume`:

```yaml
persistence:
  # Nextcloud files (/var/www/html)
  enabled: true
  accessMode: ReadWriteOnce
  size: 2Gi
```

Delete the Helm relase and create it again with the new values:

```bash
helm delete my-release
helm install my-release nextcloud/nextcloud -f manifests/values_volume.yaml
```

If we now view the created resources, we can see that a `PersistentVolumeClaim` was created:

```bash
kubectl get pod,svc,deployment,rs,pvc -l app.kubernetes.io/instance=my-release
```

<details>
<summary>Expected Output</summary>

```text
NAME                                        READY   STATUS    RESTARTS   AGE
pod/my-release-nextcloud-55d788d8d4-qlf8s   1/1     Running   0          71s

NAME                           TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/my-release-nextcloud   LoadBalancer   172.16.118.18   10.24.1.20    8080:32570/TCP   71s

NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/my-release-nextcloud   1/1     1            1           71s

NAME                                              DESIRED   CURRENT   READY   AGE
replicaset.apps/my-release-nextcloud-55d788d8d4   1         1         1       71s

NAME                                                   STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/my-release-nextcloud-nextcloud   Bound    pvc-44876df7-80f1-468a-a39e-9f64cd8e9c58   2Gi        RWO            longhorn       <unset>                 71s
```
</details>

## Nextcloud with external Postgres Cluster

In the previous chapter we have used the PostgreSQL operator to quickly spin up a highly-available Postgres cluster. Nextcloud supports as database backend. Wouldn't it be great if we could use such a database cluster for Nextcloud?

We can configure the Helm Chart to do exactly that: instead of using the internal sqlite3 database, we can configure the chart to use an external postgres cluster.

Let's first create a new Postgres cluster using the operator:

```bash
kubectl apply -f manifests/postgres_cluster.yml
```

The operator now spins up the cluster:

```bash
kubectl get pods -l app.kubernetes.io/instance=pg-nextcloud
```

<details>
<summary>Expected Output</summary>

```text
NAME             READY   STATUS    RESTARTS   AGE
pg-nextcloud-1   1/1     Running   0          16m
pg-nextcloud-2   1/1     Running   0          16m
pg-nextcloud-3   1/1     Running   0          16m
```
</details>

How do we get the password for the database? The operator creates a `Secret` which contains the credentials:

```bash
kubectl describe secret pg-nextcloud-app
```

<details>
<summary>Expected Output</summary>

```text
Name:         pg-nextcloud-app
Namespace:    default
Labels:       app.kubernetes.io/managed-by=cloudnative-pg
              cnpg.io/cluster=pg-nextcloud
              cnpg.io/reload=true
              cnpg.io/userType=app
Annotations:  cnpg.io/operatorVersion: 1.30.0

Type:  kubernetes.io/basic-auth

Data
====
dbname:         9 bytes
fqdn-jdbc-uri:  163 bytes
fqdn-uri:       144 bytes
host:           15 bytes
jdbc-uri:       145 bytes
password:       64 bytes
pgpass:         106 bytes
port:           4 bytes
uri:            126 bytes
user:           9 bytes
username:       9 bytes
```
</details>

In the secret, we can see a field `password`, which contains the randomly generated password. We can read it using:

```bash
PASSWORD=$(kubectl get secret pg-nextcloud-app -o jsonpath='{.data.password}' | base64 -d)
echo $PASSWORD
```

Like in the previous chapter, we can connect to the Postgres cluster and dump all tables:

```bash
kubectl exec pg-nextcloud-1 -c postgres -- env PGPASSWORD="$PASSWORD" psql -h localhost -U nextcloud -d nextcloud -c "\dt"
```

Currently, no tables are present.

<details>
<summary>Expected Output</summary>

```text
echo $PASSWORD
Pnb9emf2ftNOJrpj2uSGxNz37MWEH1TjIjDw7eV9hGf4HvbmGFHOL1WMdKqvDfPJ

Did not find any tables.
```
</details>

Now we must configure Nextcloud to use the database cluster. For this purpose, we deactivate the internal database in the Helm values:

```yaml
internalDatabase:
  enabled: false
```

Afterwards, we configure the connection parameters to the external database. Since the password is randomly generated, we cannot hardcode it. Luckily, its a common pattern to specify an existing `Secret` and key contained in that `Secret` to reference the contained value, i.e. the database password:

```yaml
externalDatabase:
  enabled: true
  type: postgresql # Supported database engines: mysql or postgresql
  host: "pg-nextcloud-rw:5432" # address of the database: pg-nextcloud-rw is the DNS name of the service, see `kubectl get svc`. rw means read-write.

  existingSecret:
    enabled: true
    secretName: pg-nextcloud-app # Name of the secret created by the postgres operator
    usernameKey: user # keys in that secret that specify username, password etc.
    passwordKey: password
    databaseKey: dbname
```

The final vlaues can be found in `values_external_postgres.yaml`.

Now we re-create the Helm release such that the database is properly initialized:

```bash
helm delete my-release

# PVC is not automatically deleted, thus manually delete it
kubectl delete pvc my-release-nextcloud-nextcloud

helm install my-release nextcloud/nextcloud -f manifests/values_external_postgres.yaml
```

After the Nextcloud `Pod` has started, we can dump the PostgreSQL tables again:

```bash
kubectl exec pg-nextcloud-1 -c postgres -- env PGPASSWORD="$PASSWORD" psql -h localhost -U nextcloud -d nextcloud -c "\dt"
```

Now we can see that Nextcloud indeed uses the database and has created lots of tables:

<details>
<summary>Expected Output</summary>

```text
                      List of tables
  Schema |            Name             | Type  |   Owner   
--------+-----------------------------+-------+-----------
  public | oc_accounts                 | table | nextcloud
  public | oc_accounts_data            | table | nextcloud
  public | oc_activity                 | table | nextcloud
  public | oc_activity_mq              | table | nextcloud

[...]

  public | oc_vcategory_to_object      | table | nextcloud
  public | oc_webauthn                 | table | nextcloud
  public | oc_webhook_listeners        | table | nextcloud
  public | oc_webhook_tokens           | table | nextcloud
(131 rows)
```
</details>

## Cleanup

```bash
bash cleanup.sh
```
