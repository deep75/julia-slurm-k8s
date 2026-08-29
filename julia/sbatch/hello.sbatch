#!/bin/bash
# sbatch/hello.sbatch - démo Julia Distributed minimale sur Slinky.
#
# Soumission (depuis un pod de login Slinky) :
#   sbatch /opt/julia-examples/sbatch/hello.sbatch
#   # suivi :
#   squeue -j <JOBID>
#
# Rappel du modèle : --ntasks = nombre de WORKERS Julia.
# Le driver (tâche 0) coordonne et reste sur son slot pendant la phase
# addprocs ; srun lance ensuite les --ntasks workers dans la même allocation.

#SBATCH --job-name=julia-hello
#SBATCH --partition=all
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --time=00:05:00
#SBATCH --chdir=/tmp
#SBATCH --output=/tmp/slurm-%j.out

set -euo pipefail

echo "hôte : $(hostname) | date : $(date)"
julia --project=/opt/julia-examples /opt/julia-examples/01_hello_distributed.jl
