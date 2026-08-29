#!/usr/bin/env bash
# 04-deploy-slurm.sh - déploie le cluster Slurm (chart `slurm` Slinky) avec
# les nœuds de calcul sous l'image Julia, puis attend que sinfo réponde.
#
# Usage :
#   ./scripts/04-deploy-slurm.sh
#   JULIA_IMAGE_REPO=ghcr.io/vous/julia-slurmd JULIA_IMAGE_TAG=v1 ./scripts/04-deploy-slurm.sh
#
# Prérequis :
#   - scripts/02-install-operator.sh exécuté (opérateur + CRDs)
#   - image Julia construite et accessible au cluster (scripts/03-build-images.sh)
#
# Étape suivante : scripts/05-run-julia-demo.sh

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

require_cmd helm "https://helm.sh/docs/intro/install/"
require_cmd kubectl "https://kubernetes.io/docs/tasks/tools/"
kubectl cluster-info >/dev/null 2>&1 || die "aucun cluster joignable"

kubectl get crd controllers.slinky.slurm.net >/dev/null 2>&1 \
    || die "CRDs slinky absentes - exécutez d'abord scripts/02-install-operator.sh"

log "déploiement du cluster Slurm '${HELM_RELEASE_SLURM}' (namespace ${SLURM_NS})…"
helm upgrade --install "${HELM_RELEASE_SLURM}" \
    oci://ghcr.io/slinkyproject/charts/slurm \
    --namespace "${SLURM_NS}" --create-namespace \
    -f k8s/00-values-slurm.yaml \
    --set "nodesets.julia.slurmd.image.repository=${JULIA_IMAGE_REPO}" \
    --set "nodesets.julia.slurmd.image.tag=${JULIA_IMAGE_TAG}"

log "ressources Slurm :"
kubectl get controller,nodesets,loginsets -n "${SLURM_NS}" 2>/dev/null \
    || kubectl get all -n "${SLURM_NS}"

info "attente des pods (ctrl+c pour interrompre)…"
kubectl get pods -n "${SLURM_NS}" -w &
WATCH_PID=$!
trap 'kill "$WATCH_PID" 2>/dev/null || true' EXIT

# --- Attente de sinfo (le cluster Slurm est prêt quand les slurmd s'enregistrent)
DEADLINE=$(( $(date +%s) + WAIT_TIMEOUT ))
until sinfo_ok; do
    if (( $(date +%s) > DEADLINE )); then
        die "sinfo toujours indisponible après ${WAIT_TIMEOUT}s - voir docs/08-troubleshooting.md"
    fi
    sleep 10
done
kill "$WATCH_PID" 2>/dev/null || true
trap - EXIT

LOGIN_POD="$(slurm_login_pod)"
log "état du cluster depuis le pod de login (${LOGIN_POD}) :"
kubectl exec -n "${SLURM_NS}" "${LOGIN_POD}" -- sinfo

info "Cluster prêt. Étape suivante : scripts/05-run-julia-demo.sh"
