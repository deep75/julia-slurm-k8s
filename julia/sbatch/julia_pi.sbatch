#!/bin/bash
# sbatch/julia_pi.sbatch - Monte-Carlo π parallèle (Monte-Carlo + pmap).
#
# Soumission (depuis un pod de login Slinky) :
#   sbatch /opt/julia-examples/sbatch/julia_pi.sbatch
#
# Récupération de la sortie : le fichier --output vit sur le pod de calcul
# (pas de FS partagé par défaut) :
#   kubectl exec -n slurm <pod-nodeset> -- cat /tmp/slurm-<JOBID>.out
# Voir docs/06-soumission-jobs.md (section « Récupérer la sortie »).

#SBATCH --job-name=julia-pi
#SBATCH --partition=all
#SBATCH --nodes=2
#SBATCH --ntasks=16
#SBATCH --cpus-per-task=2
#SBATCH --time=00:15:00
#SBATCH --chdir=/tmp
#SBATCH --output=/tmp/slurm-%j.out

set -euo pipefail

echo "hôte : $(hostname) | date : $(date)"
echo "SLURM_NTASKS=${SLURM_NTASKS:-?} SLURM_CPUS_PER_TASK=${SLURM_CPUS_PER_TASK:-?}"

julia --project=/opt/julia-examples /opt/julia-examples/02_monte_carlo_pi.jl
