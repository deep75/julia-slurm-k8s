# 03_pmap_eigen.jl
#
# Calcul linéaire dense embarrassamment parallèle avec pmap :
# décomposition spectrale d'un lot de matrices aléatoires, avec
# reprise sur panne de worker (retry_delays).
#
# Lancement :
#   sbatch (voir julia_pi.sbatch, changer le script) ou salloc interactif.

using Distributed
using LinearAlgebra
using Printf
using SlurmClusterManager

const NTASKS = parse(Int, get(ENV, "SLURM_NTASKS", "0"))
NTASKS == 0 && error("exécutez ce script dans une allocation Slurm (sbatch/salloc)")

# launch_timeout est un kwarg du constructeur SlurmManager, pas de addprocs.
addprocs(SlurmManager(; launch_timeout = 300.0))

const NMATRICES = get(ENV, "N_MATRICES", "256") |> s -> parse(Int, s)
const SIZE = 512

@info "Décomposition spectrale" matrices = NMATRICES taille = SIZE workers = nworkers()

@everywhere begin
    using LinearAlgebra
    using Random

    "Travail par tâche : norme spectrale (plus grande valeur propre en module)."
    function spectral_norm_seed(seed::UInt64, n::Int)
        rng = Xoshiro(seed)
        a = Symmetric(randn(rng, n, n))
        return opnorm(a, 2)  # = max |valeur propre| pour une matrice symétrique
    end
end

jobid_hash = hash(get(ENV, "SLURM_JOB_ID", "local"))

t0 = time()
# Le nombre de tentatives = length(retry_delays) ; pas de kwarg `retry_n` dans pmap.
norms = pmap(1:NMATRICES; retry_delays = ones(3), on_error = rethrow) do i
    spectral_norm_seed(UInt64(hash(i, jobid_hash)), SIZE)
end
elapsed = time() - t0

@printf("normes spectrales calculées : %d matrices %dx%d en %.2f s\n",
        length(norms), SIZE, SIZE, elapsed)
@printf("moyenne=%.3f  min=%.3f  max=%.3f\n",
        sum(norms) / length(norms), minimum(norms), maximum(norms))

# Référence séquentielle (petit lot) pour estimer le speedup.
t1 = time()
serial_batch = min(8, NMATRICES)
foreach(i -> spectral_norm_seed(UInt64(hash(i, jobid_hash)), SIZE), 1:serial_batch)
serial_time = (time() - t1) * NMATRICES / serial_batch

@printf("temps séquentiel équivalent ≈ %.2f s → speedup ≈ %.1fx sur %d workers\n",
        serial_time, serial_time / elapsed, nworkers())

rmprocs(workers(); waitfor = 60)
@info "Terminé."
