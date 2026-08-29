#!/usr/bin/env bash
# 03-build-images.sh - construit l'image de calcul `julia-slurmd`
# (slurmd Slinky + Julia + projet/depot précompilés) et la rend disponible
# au cluster.
#
# Usage :
#   ./scripts/03-build-images.sh                       # build + kind load si kind
#   PUSH=1 ./scripts/03-build-images.sh                # build + docker push
#   JULIA_IMAGE_REPO=ghcr.io/vous/julia-slurmd ./scripts/03-build-images.sh
#
# Variables d'environnement (voir lib/common.sh) :
#   JULIA_IMAGE_REPO  dépôt cible         (défaut : julia-slurmd, tag local kind)
#   JULIA_IMAGE_TAG   tag cible           (défaut : 26.05-julia1.12)
#   JULIA_VERSION     version de Julia    (défaut : 1.12.7)
#   PUSH=1            pousse vers le registry après le build
#
# Étape suivante : scripts/04-deploy-slurm.sh

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

require_cmd docker "docker (ou un runtime OCI compatible) est requis pour construire l'image"

# Cohérence tag/Julia version (le tag par défaut encode la version).
if [[ "${JULIA_IMAGE_TAG}" == "26.05-julia1.12" && "${JULIA_VERSION}" != 1.12.* ]]; then
    warn "JULIA_VERSION=${JULIA_VERSION} mais le tag reste ${JULIA_IMAGE_TAG}"
    warn "Ajustez JULIA_IMAGE_TAG pour refléter la version réelle."
fi

log "construction de ${JULIA_IMAGE} (contexte = racine du dépôt)…"
docker build \
    -f docker/julia-slurm/Dockerfile \
    --build-arg JULIA_VERSION="${JULIA_VERSION}" \
    --build-arg SLURM_IMAGE="ghcr.io/slinkyproject/slurmd:26.05-ubuntu26.04" \
    -t "${JULIA_IMAGE}" \
    .

log "image construite : $(docker image inspect "${JULIA_IMAGE}" --format '{{.Id}}')"

# --- Mise à disposition du cluster --------------------------------------------
if kind_cluster_exists; then
    log "chargement de l'image dans kind (${KIND_CLUSTER_NAME})…"
    kind load docker-image "${JULIA_IMAGE}" --name "${KIND_CLUSTER_NAME}"
    info "NB : le chart sera déployé avec repository=${JULIA_IMAGE_REPO} tag=${JULIA_IMAGE_TAG}"
elif [[ "${PUSH:-0}" == "1" ]]; then
    log "push de ${JULIA_IMAGE}…"
    docker push "${JULIA_IMAGE}"
    info "image publiée. Assurez-vous que le cluster peut la tirer (secret pull si privé)."
else
    warn "aucun kind détecté et PUSH != 1 : l'image reste locale à ce poste."
    warn "Pour un cluster distant : PUSH=1 ./scripts/03-build-images.sh (registry joignable requis)."
fi

info "Étape suivante : scripts/04-deploy-slurm.sh"
