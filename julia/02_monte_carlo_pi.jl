# 02_monte_carlo_pi.jl
#
# Estimation de π par Monte-Carlo, parallélisée sur les workers Slurm.
# Démontre le patron canonique :
#   sbatch (allocation) → driver Julia (tâche 0) → addprocs(SlurmManager())
#   → pmap/@distributed sur les workers.
#
# Lancement :
#   sbatch /opt/julia-examples/sbatch/julia_pi.sbatch
#   # ou, en interactif :
#   salloc -N 2 --ntasks=16 bash
#   julia --project=/opt/julia-examples /opt/julia-examples/02_monte_carlo_pi.jl

using Distributed
using Random
using SlurmClusterManager

const N = get(ENV, "PI_SAMPLES", "100_000_000") |> s -> parse(Int, replace(s, "_" => ""))

@info "Allocation Slurm" samples = N workers_awaited = get(ENV, "SLURM_NTASKS", "?")

addprocs(SlurmManager(); launch_timeout = 300.0)

# Plusieurs morceaux par worker → meilleur équilibrage (calculé APRÈS addprocs).
const CHUNKS = 8 * nworkers()

@info "Monte-Carlo π" samples = N chunks = CHUNKS workers = nworkers()

@everywhere begin
    using Random

    """
    Compte les points tombés dans le quart de disque unitaire.
    `seed` dérivé de (jobid, chunk) → reproductible sans dépendance externe.
    """
    function pi_chunk(n::Int, seed::UInt64)
        rng = Xoshiro(seed)
        inside = 0
        @inbounds for _ in 1:n
            x = rand(rng)
            y = rand(rng)
            inside += (x * x + y * y) <= 1.0
        end
        return inside
    end
end

# Morceaux étiquetés de façon déterministe : reproductibilité garantie
# indépendamment de l'ordonnancement des workers.
jobid_hash = hash(get(ENV, "SLURM_JOB_ID", "local"))
seeds = UInt64[hash(k, jobid_hash) for k in 1:CHUNKS]
per_chunk = cld(N, CHUNKS)

t0 = time()
counts = pmap(s -> pi_chunk(per_chunk, s), seeds)
elapsed = time() - t0

pi_est = 4.0 * sum(counts) / (per_chunk * CHUNKS)
abs_err = abs(pi_est - π)

@printf("π ≈ %.8f  (erreur absolue %.2e)\n", pi_est, abs_err)
@printf("%d échantillons × %d morceaux sur %d workers en %.2f s\n",
        per_chunk, CHUNKS, nworkers(), elapsed)

# Vérification statistique : à N grand, l'erreur doit rester modérée.
@assert abs_err < 0.01 "estimation hors tolérance : $pi_est"
println("OK - π estimé à $(abs_err < 1e-3 ? "moins de 1e-3" : "moins de 1e-2") près.")

rmprocs(workers(); waitfor = 60)
@info "Terminé."
