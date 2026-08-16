# kubernetes-workshop

This workshop offers a practical entry into Kubernetes based on [K3s](https://k3s.io/). The workshop is organized into self-contained chapters, which gradually introduce new concepts and examples. Every chapter provides the nessesary resource manifests and `kubectl` commands, alongside expected outputs to follow along.

**Usage of AI Tools**: some of the examples for resource manifests and scripts in this repository have been drafted by AI. The resource manifests and scripts were manually validated afterwards and adjusted if nessesary. AI was used in the writing process for language improvements.

## Chapters

0. [Introduction](00-introduction/README.md)
1. [Cluster-Setup](01-cluster-setup/README.md)
2. [Namespaces](02-namespaces/README.md)
3. [Pods](03-pods/README.md)
4. [Labels & Annotations](04-labels-annotations/README.md)
5. [Services](05-services/README.md)
6. [ConfigMaps & Secrets](06-configmaps-secrets/README.md)
7. [Volumes](07-volumes/README.md)
8. [Workloads](08-workloads/README.md)
9. [RBAC](09-rbac/README.md)
10. [Custom Resources & Custom Controller](10-crds-controllers/README.md)
11. [Operators](11-operators/README.md)
12. [Helm & Helm Charts](12-helm/README.md)

## Prerequisites

**Recommended Prior Experience**

This workshop assumes that you are comfortable with Linux and the command-line, and know your way around tools like SSH.

Additionally, it is recommended to be familiar with Docker and Docker Compose, as many concepts will be much clearer and easier to follow. If you dont know anything about containerization, I recommend you to follow the [Introduction to Selfhosting](https://github.com/PhilipJonasFranz/selfhosting-workshop) workshop before you jump into the rabbit hole that is Kubernetes.

**Required Infrastructure**

You will need 3 devices or VMs running preferably Ubuntu Server. Other Linux distributions will likely work as well, but this workshop has been written for Ubuntu, specifically Ubuntu Server 26.04. The nodes do not need lots of computing power, so even something like a RaspberryPi should be enough. The workshop has been tested with VMs with 2 vCPUs and 2GB memory each. Additionally, the Nodes should all be within the same subnet and should be able to ping each other. The VMs also require internet access to pull container images and dependencies.

If you dont have 3 nodes to work with, you can use [Kind](https://kind.sigs.k8s.io/), which runs a Kubernetes cluster inside a Docker container. Please note that while this setup should work for most examples in this workshop, it has not been validated, and demos like Longhorn or demos that require multiple nodes will likely not work.

## Workflow

Before starting, rename the `.env.sample` to `.env` and adjust the contained values. Afterwards run the templating script to replace placeholder values in this repository with the configured ones:

```bash
bash template.sh
```

This step is optional, but can help to prevent manual edits in files later. All `kubectl` commands in the chapters assume that they are run from within the associated chapter directory, such that `manifests/...` paths are working properly, e.g.:

```bash
cd 03-pods
kubectl apply -f manifests/pod_nginx_init.yml
```

After completing a chapter, the cluster can be wiped using the cleanup script:

```bash
bash cleanup.sh
```

The script deletes all non-essential cluster namespaces and resources, and empties the `default` namespace. Only use this script in a testing environment, and use at your own risk!

## License

This work is licensed under a
[Creative Commons Attribution 4.0 International License][cc-by].

[![CC BY 4.0][cc-by-image]][cc-by]

[cc-by]: http://creativecommons.org/licenses/by/4.0/
[cc-by-image]: https://i.creativecommons.org/l/by/4.0/88x31.png
[cc-by-shield]: https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg