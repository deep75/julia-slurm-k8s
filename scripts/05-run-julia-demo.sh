#!/usr/bin/env bash
# 05-run-julia-demo.sh - soumet les exemples Julia sur le cluster Slurm
# depuis le pod de login, puis récupère la sortie.
#
# Usage :
#   ./scripts/05-run-julia-demo.sh hello      # (défaut) addprocs minimal
#   ./scripts/05-run-julia-demo.sh pi         # Monte-Carlo π parallèle
#   ./scripts/05-run-julia-demo.sh options    # démonstration des kwargs
#   ./scripts/05-run-julia-demo.sh eigen      # pmap + LinearAlgebra
#   ./scripts/05-run-julia-demo.sh exec       # shell interactif sur le pod de login
#
# Modèle de soumission : le script sbatch est copié dans le pod de login
# (kubectl cp) puis sbatch transmet son CONTENU au contrôleur - les pods de
# calcul n'ont pas besoin du fichier, seulement de l'image Julia.
# Les exemples options/eigen sont soumis via `sbatch --wrap` (sans fichier).
# La sortie (--output=/tmp/slurm-<JOBID>.out) vit sur le POD DE CALCUL :
# on la relit via kubectl exec. Détails : docs/06-soumission-jobs.md.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

require_cmd kubectl "https://kubernetes.io/docs/tasks/tools/"

DEMO="${1:-hello}"
SBATCH_FILE=""
SBATCH_WRAP=""
case "$DEMO" in
    hello)
        SBATCH_FILE="julia/sbatch/hello.sbatch"
        ;;
    pi)
        SBATCH_FILE="julia/sbatch/julia_pi.sbatch"
        ;;
    options)
        SBATCH_WRAP="julia --project=/opt/julia-examples /opt/julia-examples/04_options_demo.jl"
        ;;
    eigen)
        SBATCH_WRAP="julia --project=/opt/julia-examples /opt/julia-examples/03_pmap_eigen.jl"
        ;;
    exec)
        LOGIN_POD="$(slurm_login_pod)" || die "pod de login introuvable dans ${SLURM_NS}"
        log "shell interactif dans ${LOGIN_POD} (sinfo, sbatch, salloc -N2 bash)…"
        exec kubectl exec -it -n "${SLURM_NS}" "${LOGIN_POD}" -- bash
        ;;
    *) die "usage : $0 {hello|pi|options|eigen|exec}" ;;
esac

sinfo_ok || die "cluster Slurm non prêt - exécutez scripts/04-deploy-slurm.sh"
LOGIN_POD="$(slurm_login_pod)" || die "pod de login introuvable"
log "pod de login : ${LOGIN_POD}"

# --- Soumission -----------------------------------------------------------------
if [[ -n "$SBATCH_FILE" ]]; then
    [[ -f "$SBATCH_FILE" ]] || die "fichier introuvable : $SBATCH_FILE"
    REMOTE_BATCH="/tmp/$(basename "$SBATCH_FILE")"
    kubectl cp -n "${SLURM_NS}" "${SBATCH_FILE}" "${LOGIN_POD}:${REMOTE_BATCH}"
    JOBID="$(kubectl exec -n "${SLURM_NS}" "${LOGIN_POD}" -- \
        sbatch --parsable "${REMOTE_BATCH}")" || die "échec de sbatch"
else
    JOBID="$(kubectl exec -n "${SLURM_NS}" "${LOGIN_POD}" -- \
        sbatch --parsable \
        --job-name="julia-${DEMO}" --partition=all --nodes=2 --ntasks=8 \
        --cpus-per-task=2 --time=00:15:00 --chdir=/tmp --output="/tmp/slurm-%j.out" \
        --wrap="${SBATCH_WRAP}")" || die "échec de sbatch --wrap"
fi

log "job Slurm soumis : ${JOBID}"
kubectl exec -n "${SLURM_NS}" "${LOGIN_POD}" -- squeue

# --- Attente de complétion -------------------------------------------------------
DEADLINE=$(( $(date +%s) + WAIT_TIMEOUT ))
while true; do
    STATE="$(kubectl exec -n "${SLURM_NS}" "${LOGIN_POD}" -- \
        scontrol show job "${JOBID}" 2>/dev/null \
        | grep -oP 'JobState=\K\w+' | head -1 || echo UNKNOWN)"
    case "$STATE" in
        COMPLETED) log "job ${JOBID} : COMPLETED" ; break ;;
        FAILED|CANCELLED|TIMEOUT|NODE_FAIL)
            die "job ${JOBID} : ${STATE} - sortie éventuelle sur le pod de calcul (voir docs/08-troubleshooting.md)" ;;
        PENDING|RUNNING|CONFIGURING|COMPLETING) ;;
        *) warn "état inattendu '${STATE}', on continue" ;;
    esac
    if (( $(date +%s) > DEADLINE )); then
        warn "timeout après ${WAIT_TIMEOUT}s (état : ${STATE})"
        warn "annulez avec : kubectl exec -n ${SLURM_NS} ${LOGIN_POD} -- scancel ${JOBID}"
        exit 1
    fi
    sleep 5
done

# --- Récupération de la sortie depuis le POD DE CALCUL ---------------------------
WORKER_POD="$(slurm_worker_pods | head -1)"
[[ -n "$WORKER_POD" ]] || die "aucun pod de calcul trouvé (motif : ${WORKER_MATCH})"
log "lecture de /tmp/slurm-${JOBID}.out sur ${WORKER_POD} :"
echo "────────────────────────────────────────────────────────────"
kubectl exec -n "${SLURM_NS}" "${WORKER_POD}" -- cat "/tmp/slurm-${JOBID}.out"
echo "────────────────────────────────────────────────────────────"
log "démo '${DEMO}' terminée."
