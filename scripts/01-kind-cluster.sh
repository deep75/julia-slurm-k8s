#!/usr/bin/env bash
# 01-kind-cluster.sh - cluster kind de démonstration local (OPTIONNEL).
#
# Usage :
#   ./scripts/01-kind-cluster.sh up      # crée le cluster (k8s/10-kind-config.yaml)
#   ./scripts/01-kind-cluster.sh down    # supprime le cluster
#   ./scripts/01-kind-cluster.sh status
#
# ⚠ Démo locale uniquement : NE JAMAIS utiliser kind pour la production.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

require_cmd kind "installez kind : https://kind.sigs.k8s.io/ (ou scripts/00-prereqs.sh --install-kind)"

case "${1:-status}" in
    up)
        if kind_cluster_exists; then
            warn "le cluster kind '${KIND_CLUSTER_NAME}' existe déjà"
        else
            log "création du cluster kind '${KIND_CLUSTER_NAME}'…"
            kind create cluster --name "${KIND_CLUSTER_NAME}" \
                --config k8s/10-kind-config.yaml \
                --wait 5m
        fi
        kubectl config use-context "kind-${KIND_CLUSTER_NAME}"
        kubectl get nodes
        info "Étape suivante : scripts/00-prereqs.sh --install-cert-manager"
        info "puis : scripts/02-install-operator.sh"
        ;;
    down)
        log "suppression du cluster kind '${KIND_CLUSTER_NAME}'…"
        kind delete cluster --name "${KIND_CLUSTER_NAME}"
        ;;
    status)
        if kind_cluster_exists; then
            log "cluster kind '${KIND_CLUSTER_NAME}' : présent"
            kubectl --context "kind-${KIND_CLUSTER_NAME}" get nodes 2>/dev/null || true
        else
            warn "cluster kind '${KIND_CLUSTER_NAME}' : absent"
        fi
        ;;
    *)
        die "usage : $0 {up|down|status}"
        ;;
esac
