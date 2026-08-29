#!/usr/bin/env bash
# 00-prereqs.sh - vérifie (et au besoin installe) les prérequis côté poste
# et côté cluster : kubectl, helm, (kind, docker en option), cert-manager,
# Kubernetes >= 1.29.
#
# Usage :
#   ./scripts/00-prereqs.sh                 # vérification seule
#   ./scripts/00-prereqs.sh --install-helm  # installe helm si absent
#   ./scripts/00-prereqs.sh --install-kind  # installe kind si absent
#   ./scripts/00-prereqs.sh --install-cert-manager  # déploie cert-manager
#
# Rien n'est installé sans flag explicite. Voir docs/02-prerequis-installation.md.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/common.sh

INSTALL_HELM=0; INSTALL_KIND=0; INSTALL_CM=0
for arg in "$@"; do
    case "$arg" in
        --install-helm) INSTALL_HELM=1 ;;
        --install-kind) INSTALL_KIND=1 ;;
        --install-cert-manager) INSTALL_CM=1 ;;
        *) die "option inconnue : $arg" ;;
    esac
done

info "Vérification des outils locaux"

if command -v kubectl >/dev/null 2>&1; then
    log "kubectl : $(kubectl version --client 2>/dev/null | head -1)"
else
    warn "kubectl absent - https://kubernetes.io/docs/tasks/tools/"
fi

if command -v helm >/dev/null 2>&1; then
    log "helm : $(helm version --short)"
elif [[ $INSTALL_HELM -eq 1 ]]; then
    log "Installation de helm (script officiel)…"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    require_cmd helm "l'installation a échoué"
else
    warn "helm absent - https://helm.sh/docs/intro/install/ (ou relancez avec --install-helm)"
fi

if command -v kind >/dev/null 2>&1; then
    log "kind : $(kind version)"
elif [[ $INSTALL_KIND -eq 1 ]]; then
    log "Installation de kind (binaire officiel)…"
    curl -fsSL -o /usr/local/bin/kind \
        https://kind.sigs.k8s.io/dl/latest/kind-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    chmod +x /usr/local/bin/kind
    log "kind installé"
else
    warn "kind absent (optionnel, pour la démo locale) - https://kind.sigs.k8s.io/"
fi

if command -v docker >/dev/null 2>&1; then
    log "docker : $(docker --version)"
else
    warn "docker absent (requis uniquement pour construire l'image Julia)"
fi

# --- Côté cluster -------------------------------------------------------------
if kubectl cluster-info >/dev/null 2>&1; then
    SERVER_MINOR="$(kubectl version -o json 2>/dev/null \
        | python3 -c 'import json,sys; v=json.load(sys.stdin)["serverVersion"]["minor"]; print(int(v.rstrip("+")))')" \
        || die "impossible de lire la version du serveur Kubernetes"
    log "cluster joignable : $(kubectl config current-context) (1.${SERVER_MINOR})"
    if [[ $SERVER_MINOR -lt 29 ]]; then
        die "Kubernetes >= 1.29 requis par le chart Slinky (trouvé : 1.${SERVER_MINOR})"
    fi
else
    die "aucun cluster joignable (kubectl cluster-info en échec). Utilisez scripts/01-kind-cluster.sh up pour un cluster de démo local."
fi

if kubectl get crd issuers.cert-manager.io >/dev/null 2>&1; then
    log "cert-manager : présent"
else
    if [[ $INSTALL_CM -eq 1 ]]; then
        log "Installation de cert-manager (requis par slurm-operator)…"
        require_cmd helm "helm est requis pour installer cert-manager"
        helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
            --namespace cert-manager --create-namespace \
            --set crds.enabled=true \
            --wait --timeout 5m
        log "cert-manager déployé"
    else
        warn "cert-manager absent - requis par slurm-operator."
        warn "Relancez avec : $0 --install-cert-manager"
    fi
fi

info "Prérequis OK. Étape suivante : scripts/02-install-operator.sh"
