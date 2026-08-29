# 04_options_demo.jl
#
# Démontre les options réellement supportées par
# addprocs(SlurmManager(); ...) et l'environnement hérité de l'allocation :
#
#   - `dir`      : répertoire de travail passé à `srun -D`
#   - `exename`  : binaire Julia des workers
#   - `exeflags` : drapeaux ajoutés à la ligne de commande des workers
#   - `env`      : variables d'environnement additionnelles (Julia ≥ 1.6)
#
# SlurmClusterManager propage automatiquement JULIA_PROJECT,
# JULIA_LOAD_PATH et JULIA_DEPOT_PATH du driver vers les workers.

using Distributed
using SlurmClusterManager

const NTASKS = parse(Int, get(ENV, "SLURM_NTASKS", "0"))
NTASKS == 0 && error("exécutez ce script dans une allocation Slurm (sbatch/salloc)")

println("== Environnement Slurm hérité par le driver ==")
for k in ("SLURM_JOB_ID", "SLURM_NTASKS", "SLURM_JOB_NUM_NODES",
          "SLURM_CPUS_PER_TASK", "SLURM_JOB_PARTITION", "SLURM_NODELIST")
    v = get(ENV, k, "-")
    println("  $k = $v")
end

# `exeflags` typique en conteneur : threads par worker (CPU binding Slurm
# reste contrôlé par --cpus-per-task de l'allocation).
worker_threads = max(1, parse(Int, get(ENV, "SLURM_CPUS_PER_TASK", "1")))

@info "addprocs avec options" exeflags = "--threads=$worker_threads"

addprocs(
    SlurmManager();
    dir = "/tmp",
    exeflags = `--threads=$worker_threads --check-bounds=yes`,
    env = ["JULIA_NUM_THREADS" => string(worker_threads)],
    launch_timeout = 300.0,
)

for w in workers()
    t = remotecall_fetch(w, () -> (gethostname(), Threads.nthreads(), pwd()))
    println("worker $w : host=$(t[1])  threads=$(t[2])  dir=$(t[3])")
end

@info "JULIA_PROJECT actif côté driver" project = Base.active_project()
proj = remotecall_fetch(first(workers()), () -> Base.active_project())
@assert proj == Base.active_project() "JULIA_PROJECT non propagé au worker"
println("JULIA_PROJECT identique driver/worker : $proj  ✓")

rmprocs(workers(); waitfor = 60)
@info "Terminé."
