# Image de calcul Slurm + Julia pour le cluster Slinky.
#
# Base : image slurmd officielle Slinky (démone slurmd + userland Slurm
# complet : srun/sbatch/scancel/sinfo...). C'est DANS ce conteneur que les
# steps Slurm s'exécutent : le driver Julia et les workers vivent ici.
#
# Contexte de build = racine du dépôt :
#   docker build -f docker/julia-slurm/Dockerfile -t <repo>/julia-slurmd:<tag> .
#
# NB : les scripts sbatch ne sont PAS embarqués dans cette image - ils sont
# lus côté client (pod de login) au moment de `sbatch`. Voir
# scripts/05-run-julia-demo.sh et docs/06-soumission-jobs.md.
#
# Voir docs/04-images-conteneurs.md.

ARG SLURM_IMAGE=ghcr.io/slinkyproject/slurmd:26.05-ubuntu26.04
FROM ${SLURM_IMAGE}

ARG JULIA_VERSION=1.12.7
ARG TARGETARCH=amd64

# Dépendances de téléchargement (wget n'est pas forcément dans l'image de base).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*

# Julia officiel (tarball glibc) dans /usr/local, binaire exposé dans le PATH.
# amd64 → https://julialang-s3.julialang.org/bin/linux/x64/.../linux-x86_64.tar.gz
# arm64 → https://julialang-s3.julialang.org/bin/linux/aarch64/.../linux-aarch64.tar.gz
# NB : pour la production, épinglez le SHA256 du tarball (voir docs/04).
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64)  julia_arch="x64";     tarball_arch="x86_64" ;; \
      arm64)  julia_arch="aarch64"; tarball_arch="aarch64" ;; \
      *) echo "TARGETARCH non supporté : ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    tarball="julia-${JULIA_VERSION}-linux-${tarball_arch}.tar.gz"; \
    wget -q -O "/tmp/${tarball}" \
      "https://julialang-s3.julialang.org/bin/linux/${julia_arch}/${JULIA_VERSION%%.*}/${tarball}"; \
    mkdir -p /usr/local/julia; \
    tar -xzf "/tmp/${tarball}" -C /usr/local/julia --strip-components=1; \
    rm "/tmp/${tarball}"; \
    ln -s /usr/local/julia/bin/julia /usr/local/bin/julia; \
    julia --version

# Projet + dépôt Julia « cuits dans l'image » :
#   - /opt/julia-examples : Project.toml + scripts d'exemple
#   - /opt/julia/depot    : JULIA_DEPOT_PATH partagé driver/workers,
#                           précompilé au build (démarrage des workers rapide)
# SlurmClusterManager propage JULIA_PROJECT/JULIA_DEPOT_PATH du driver vers
# les workers : chemins identiques car même image → rien à partager via NFS.
COPY julia/ /opt/julia-examples/
ENV JULIA_DEPOT_PATH=/opt/julia/depot \
    JULIA_PROJECT=/opt/julia-examples

RUN julia --project=/opt/julia-examples -e '\
    using Pkg; \
    Pkg.instantiate(); \
    Pkg.precompile(); \
    using SlurmClusterManager, Distributed, Random, LinearAlgebra' \
 && echo "depot Julia précompilé."
