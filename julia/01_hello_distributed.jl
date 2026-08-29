# 01_hello_distributed.jl
#
# Exemple minimal : transforme toutes les tâches d'une allocation Slurm en
# workers Julia Distributed et affiche leur identité.
#
# Prérequis (contrat de SlurmClusterManager.jl) :
#   - le driver DOIT tourner dans une allocation Slurm
#     (SLURM_JOB_ID et SLURM_NTASKS définies) ;
#   - `srun` disponible dans le PATH de l'image.
#
# Lancement depuis un pod de login Slinky :
#   sbatch /opt/julia-examples/sbatch/hello.sbatch
#
# Voir docs/05-julia-distributed-slurm.md pour les détails.

using Distributed
using SlurmClusterManager

const JOBID  = get(ENV, "SLURM_JOB_ID", get(ENV, "SLURM_JOBID", ""))
const NTASKS = parse(Int, get(ENV, "SLURM_NTASKS", "0"))

if isempty(JOBID) || NTASKS == 0
    error("""
    Ce script doit être exécuté DANS une allocation Slurm.
    Variables manquantes : SLURM_JOB_ID / SLURM_NTASKS.
    Utilisez : sbatch /opt/julia-examples/sbatch/hello.sbatch
    """)
end

@info "Allocation Slurm détectée" jobid = JOBID ntasks = NTASKS hostname = gethostname()

# SlurmManager() n'accepte AUCUN argument Slurm (partition, ntasks...) :
# toute la topologie vient de l'allocation sbatch/salloc existante.
# Kwarg utiles uniquement : launch_timeout, srun_post_exit_sleep.
@info "Lancement des workers via srun..."
addprocs(SlurmManager(); launch_timeout = 300.0)

@info "Workers connectés" nworkers = nworkers() procs = procs()

# Chaque worker imprime son identité - la sortie est redirigée vers le
# stdout du driver par SlurmClusterManager (pas de fichier par tâche).
@everywhere workers() println("bonjour depuis worker $(myid()) @ $(gethostname())" *
                              " (threads=$(Threads.nthreads()))")

@info "Vérification : somme 1..1_000_000 calculée côté workers"
total = sum(remotecall_fetch(w, x -> sum(1:x), 1_000_000) for w in workers())
expected = 500_000_500_000
@assert total == expected "somme incorrecte : $total != $expected"
println("somme 1..1_000_000 par worker : OK ($total)")

# Libère les workers proprement avant la fin du step.
rmprocs(workers(); waitfor = 60)
@info "Terminé."
