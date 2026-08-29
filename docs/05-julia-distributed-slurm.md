# 05 - Julia Distributed sur Slurm

← [04 - Images conteneurs](04-images-conteneurs.md) | [06 - Soumission de jobs →](06-soumission-jobs.md)

Ce chapitre est le cœur du dépôt : le contrat exact de
[`SlurmClusterManager.jl` v1.1.0](https://github.com/JuliaParallel/SlurmClusterManager.jl)
et son fonctionnement sur Slinky.

## 1. Le contrat d'allocation

`SlurmManager()` est **le seul constructeur** et il n'accepte **aucun argument
Slurm** (pas de `partition`, `ntasks`, `gres`…). Il exige au moment de sa
construction :

| Variable d'environnement | Rôle | Sinon |
|---|---|---|
| `SLURM_JOB_ID` (ou legacy `SLURM_JOBID`) | identifie l'allocation courante | **erreur** |
| `SLURM_NTASKS` | nombre de workers à attendre | **erreur** |

Conséquence architecturale : le driver Julia est **lancé par sbatch/salloc**
(voir [06](06-soumission-jobs.md)). Toute la topologie (partition, tâches,
CPU, mémoire, GPU) est décidée **par l'allocation**, jamais par Julia.

```mermaid
flowchart LR
    subgraph bon["✅ patron correct"]
        SB["sbatch / salloc<br/>--ntasks=16"] --> AL["allocation SLURM_*"] --> SM["SlurmManager()"]
    end
    subgraph faux["❌ patrons impossibles"]
        RE["REPL / pod libre"] --> X1["erreur : SLURM_JOB_ID manquant"]
        SMK["addprocs(SlurmManager(), partition=…)"] --> X2["aucun kwarg Slurm<br/>(launch_timeout, srun_post_exit_sleep seuls)"]
    end
```

Les kwargs supportés par `addprocs(SlurmManager(); …)` :

| Kwarg | Défaut | Effet |
|---|---|---|
| `launch_timeout` | `60.0` s | délai max d'attente des connexions workers (mettre 300 en conteneur) |
| `srun_post_exit_sleep` | `0.01` s | pause après sortie de srun (laisser Slurm enregistrer l'exit) |
| `dir` | `pwd()` | répertoire de travail passé à `srun -D` |
| `exename` | `Sys.BINDIR/julia` | binaire Julia des workers |
| `exeflags` | - | drapeaux ajoutés aux workers (ex. `--threads=N`) |
| `env` | - | variables ajoutées aux workers (Julia ≥ 1.6) |

Propagation automatique driver → workers : **`JULIA_PROJECT`**,
**`JULIA_LOAD_PATH`**, **`JULIA_DEPOT_PATH`** (via `addenv` sur srun).

## 2. Mécanisme interne

```mermaid
sequenceDiagram
    autonumber
    participant D as Driver julia
    participant M as SlurmManager
    participant SR as srun (process local)
    participant CT as slurmctld
    participant ND as pods slurmd
    participant W as julia --worker

    D->>M: addprocs(SlurmManager())
    Note over M: lit SLURM_JOB_ID + SLURM_NTASKS<br/>erreur si absents
    M->>SR: open(`srun -D $dir julia $exeflags --worker`)
    M->>SR: write(cookie de cluster + "\n")  % via STDIN - pas de SSH
    SR->>CT: step de NTASKS tâches dans l'allocation
    CT->>ND: lancement sur les nœuds alloués
    ND->>W: exec julia --worker (cookie reçu par stdin)
    W->>W: bind socket TCP éphémère
    W-->>D: imprime "host:port#..." sur stdout srun
    Note over D: tâche @async parse "host:port" ligne à ligne
    D->>W: accepte la connexion TCP (WorkerConfig host+port)
    Note over D,W: sortie des workers redirigée vers stdout du driver
```

Sur Slinky, `host` imprimé par le worker est le hostname du pod (`worker-0`,
`worker-1`…) - résolvable grâce au headless service
`slurm-workers-<controller>` (voir [01 §2](01-architecture.md)). Aucun port à
exposer manuellement : sockets **éphémères**, connexions **pod → pod**.

## 3. Topologie obtenue

```mermaid
flowchart TB
    subgraph pod0["pod worker-0"]
        D["driver julia (tâche 0)"]
        W1["worker 2"]
        W2["worker 3"]
    end
    subgraph pod1["pod worker-1"]
        W3["worker 4"]
        W4["worker 5"]
    end
    D -->|"pmap / @distributed / remotecall"| W1
    D --> W2
    D --> W3
    D --> W4
    W1 & W2 & W3 & W4 -.->|"TCP (host:port)"| D
```

## 4. Différence avec l'ancien `ClusterManagers.jl`

| Aspect | `ClusterManagers.SlurmManager` (déprécié) | `SlurmClusterManager.SlurmManager` (ce dépôt) |
|---|---|---|
| Soumission d'un job | possible depuis un nœud de login | **interdit** : doit être dans une allocation |
| Kwarg `np` / flags Slurm | oui | **non** |
| Découverte des workers | fichiers `.out` sur disque | stdout de srun (stream) |
| Sortie workers | fichiers par tâche | redirigée vers le driver |
| Auth worker | SSH ou cookie en arg | cookie par **stdin**, pas de SSH |

`ClusterManagers.jl` émet un `depwarn` renvoyant explicitement vers ce package.

## 5. Bonnes pratiques sur Slinky

1. **`launch_timeout=300.0`** : le premier `srun` d'une image fraîchement
   déployée peut être lent (pull image, cold start).
2. **Threads vs tâches** : `--cpus-per-task=2` à l'allocation +
   `exeflags="--threads=2"` côté workers ; ne doublez pas les deux.
3. **Projet actif** : lancez toujours `julia --project=/opt/julia-examples`
   (ou `JULIA_PROJECT` env) pour que la propagation couvre les workers.
4. **Données volumineuses** : partagez par volume RWX monté sur le NodeSet
   (`slurmd.volumeMounts`), pas par le depot image.
5. **Arrêt propre** : `rmprocs(workers(); waitfor=60)` avant la fin du script
   - évite les steps orphelins et les « Waiting up to 32 seconds ».
6. **Vérifiez l'environnement** : `julia/04_options_demo.jl` imprime les
   variables `SLURM_*` héritées et teste la propagation du project.

→ Suivant : [06 - Soumission de jobs](06-soumission-jobs.md)
