#!/usr/bin/env bash

set -euo pipefail

PROTECTED_NAMESPACES="kube-system kube-public kube-node-lease default longhorn-system metallb-system"

# Delete all non-protected namespaces
for ns in $(kubectl get namespace -o jsonpath='{.items[*].metadata.name}'); do
  [[ " $PROTECTED_NAMESPACES " == *" $ns "* ]] || kubectl delete namespace "$ns" --ignore-not-found --wait=false
done


# Delete all resources in the default namespace
kubectl delete pods,deployments,replicasets,statefulsets,daemonsets,jobs,cronjobs,replicationcontrollers,secret,pvc,role,rolebinding --all -n default --ignore-not-found

# Delete all resources of a certain type, excluding specified resources
delete_except() {
  local resource="$1" keep="$2"
  for name in $(kubectl get "$resource" -n default -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    [[ "$name" == "$keep" ]] || kubectl delete "$resource" "$name" -n default --ignore-not-found
  done
}

delete_except service kubernetes
delete_except configmap kube-root-ca.crt
delete_except serviceaccount default

# RBAC resources
kubectl delete clusterrolebinding node-reader-binding --ignore-not-found
kubectl delete clusterrole node-reader --ignore-not-found

# sample-controller related CRD
kubectl delete crd foos.samplecontroller.k8s.io --ignore-not-found

# Postgres Operator resources
kubectl get crd -o name 2>/dev/null | { grep '\.postgresql\.cnpg\.io$' || true; } | xargs -r kubectl delete
kubectl get clusterrole -o name 2>/dev/null | { grep '^clusterrole\.rbac\.authorization\.k8s\.io/cnpg-' || true; } | xargs -r kubectl delete
kubectl delete clusterrolebinding cnpg-manager-rolebinding --ignore-not-found
kubectl delete mutatingwebhookconfiguration cnpg-mutating-webhook-configuration --ignore-not-found
kubectl delete validatingwebhookconfiguration cnpg-validating-webhook-configuration --ignore-not-found

# Other resources that may be left over
kubectl delete pv busybox-pv --ignore-not-found
kubectl delete storageclass local-path-retain --ignore-not-found
