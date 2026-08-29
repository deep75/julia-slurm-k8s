#!/usr/bin/env bash
# 02-install-operator.sh - déploie slurm-operator (CRDs + opérateur) via Helm.
#
# Usage :
#   ./scripts/02-install-operator.sh
#   PROMETHEUS=1 ./scripts/02-install-operator.sh   # + kube-prometheus-stack
#
# Charts (registry OCI ghcr.io/slinkyproject/charts) :
#   1. slurm-operator-crds  - définitions CRD (portée cluster, sans namespace)
#   2. slurm-operator       - opérateur (namespace slinky)
#
# Étape suivante : scripts/03-build-images.sh puis scripts/04-deploy-slurm.sh.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

require_cmd helm "https://helm.sh/docs/intro/install/"
require_cmd kubectl "https://kubernetes.io/docs/tasks/tools/"
kubectl cluster-info >/dev/null 2>&1 || die "aucun cluster joignable"

# 1) CRDs ---------------------------------------------------------------------
log "installation des CRDs slurm-operator…"
helm upgrade --install slurm-operator-crds \
    oci://ghcr.io/slinkyproject/charts/slurm-operator-crds

log "CRDs installées :"
kubectl get crds | grep slinky.slurm.net || die "CRDs slinky absentes après install"

# 2) Opérateur -----------------------------------------------------------------
log "installation de slurm-operator (namespace ${SLINKY_NS})…"
helm upgrade --install slurm-operator \
    oci://ghcr.io/slinkyproject/charts/slurm-operator \
    --namespace "${SLINKY_NS}" --create-namespace

kubectl -n "${SLINKY_NS}" rollout status deployment -l app.kubernetes.io/instance=slurm-operator \
    --timeout=300s || warn "rollout non confirmé - inspectez : kubectl -n ${SLINKY_NS} get pods"
kubectl -n "${SLINKY_NS}" get pods

# 3) Optionnel : Prometheus (métriques slurmctld / GPU DCGM) -------------------
if [[ "${PROMETHEUS:-0}" == "1" ]]; then
    log "installation de kube-prometheus-stack…"
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace prometheus --create-namespace \
        --wait --timeout 10m
    info "Pensez à relancer scripts/04-deploy-slurm.sh avec :"
    info "  --set controller.metrics.enabled=true --set controller.metrics.serviceMonitor.enabled=true"
fi

info "Opérateur déployé. Étape suivante : scripts/03-build-images.sh"
