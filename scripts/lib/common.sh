#!/usr/bin/env bash
# lib/common.sh - helpers partagés par tous les scripts de ce dépôt.
# Source : source "$(dirname "$0")/lib/common.sh"

# Ne pas mettre set -euo pipefail ici : chaque script appelant le fait.

# --- Couleurs ---------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_BLUE=$'\e[34m'
else
    C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi

log()   { printf '%s[+]%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
info()  { printf '%s[i] %s %s\n' "${C_BLUE}" "${C_RESET}" "$*"; }
warn()  { printf '%s[!]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
die()   { printf '%s[x] %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }

# Racine du dépôt (indépendante du répertoire courant).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Dépendances ------------------------------------------------------------
require_cmd() {
    local cmd="$1" hint="${2:-}"
    command -v "$cmd" >/dev/null 2>&1 || \
        die "'$cmd' introuvable. ${hint}"
}

# --- Paramètres d'environnement (surchargeables) -----------------------------
: "${SLINKY_NS:=slinky}"          # namespace de l'opérateur
: "${SLURM_NS:=slurm}"            # namespace du cluster Slurm
: "${HELM_RELEASE_SLURM:=slurm}"  # release helm du cluster Slurm
: "${KIND_CLUSTER_NAME:=julia-slurm}"
: "${JULIA_IMAGE_REPO:=julia-slurmd}"          # tag local kind par défaut
: "${JULIA_IMAGE_TAG:=26.05-julia1.12}"
: "${JULIA_VERSION:=1.12.7}"                   # version de Julia dans l'image
: "${WAIT_TIMEOUT:=600}"                       # secondes d'attente max (sinfo)
# Motif pour reconnaître les pods de calcul (nom du NodeSet dans les values).
: "${WORKER_MATCH:=julia}"

export SLINKY_NS SLURM_NS HELM_RELEASE_SLURM KIND_CLUSTER_NAME \
       JULIA_IMAGE_REPO JULIA_IMAGE_TAG JULIA_VERSION WAIT_TIMEOUT WORKER_MATCH

JULIA_IMAGE="${JULIA_IMAGE_REPO}:${JULIA_IMAGE_TAG}"

# --- Découverte de pods ------------------------------------------------------
# Pod de login : nécessaire pour soumettre (sbatch/srun) - c'est le client Slurm.
slurm_login_pod() {
    kubectl get pods -n "${SLURM_NS}" -o name 2>/dev/null \
        | grep -m1 'pod/.*login' | cut -d/ -f2
}

# Pods de calcul (NodeSet) : noms contenant ${WORKER_MATCH}, en excluant
# contrôleur/login/restapi/comptabilité.
slurm_worker_pods() {
    kubectl get pods -n "${SLURM_NS}" -o name 2>/dev/null \
        | cut -d/ -f2 \
        | grep -v -E 'controller|login|restapi|accounting|dbd|operator|munge' \
        | grep "${WORKER_MATCH}" || true
}

# Vérifie que le cluster Slurm répond (sinfo) depuis le pod de login.
sinfo_ok() {
    local pod
    pod="$(slurm_login_pod)" || return 1
    [[ -n "$pod" ]] || return 1
    kubectl exec -n "${SLURM_NS}" "$pod" -- sinfo --noheader 2>/dev/null | grep -q 'idle\|mixed\|alloc'
}

# --- kind ---------------------------------------------------------------------
kind_cluster_exists() {
    kind get clusters 2>/dev/null | grep -qx "${KIND_CLUSTER_NAME}"
}
