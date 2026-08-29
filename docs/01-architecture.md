# 01 - Architecture

← [README](../README.md) | [02 - Prérequis →](02-prerequis-installation.md)

Ce chapitre décrit comment Slinky compose un cluster Slurm dans Kubernetes et
où se place Julia dans ce modèle.

## 1. Les pièces de Slinky

L'opérateur (`slurm-operator`, namespace `slinky`) surveille six CRDs
(`slinky.slurm.net/v1beta1`) et matérialise les charges dans le namespace du
cluster Slurm (`slurm` dans ce dépôt). Il n'existe **pas** de CRD
`SlurmCluster` monolithique.

```mermaid
flowchart TB
    subgraph nsSlinky["namespace slinky"]
        OP["slurm-operator<br/>(deployment)"]
    end

    subgraph crds["CRDs slinky.slurm.net/v1beta1"]
        C["Controller<br/>= slurmctld"]
        N["NodeSet<br/>= slurmd (calcul)"]
        L["LoginSet<br/>= pods clients"]
        A["Accounting<br/>= slurmdbd (option)"]
        R["RestAPI<br/>= slurmrestd (option)"]
        T["Token<br/>= jetons JWT (option)"]
    end

    subgraph nsSlurm["namespace slurm (chart slurm)"]
        PC["pod slurmctld :6817<br/>+ PVC état"]
        PW0["pod worker-0<br/>slurmd :6818 + Julia"]
        PW1["pod worker-1<br/>slurmd :6818 + Julia"]
        PL["pod login<br/>clients sbatch/srun"]
        SVC["svc slurm-controller<br/>svc slurm-workers-headless<br/>svc slurm-login-julia"]
    end

    OP -->|"reconcile"| C
    OP -->|"reconcile"| N
    OP -->|"reconcile"| L
    OP -.->|"optionnel"| A
    OP -.->|"optionnel"| R
    C -->|"crée"| PC
    N -->|"crée"| PW0
    N -->|"crée"| PW1
    L -->|"crée"| PL
    C -->|"génère"| SVC
```

Points clés :

- **Configless** : chaque `slurmd` récupère sa configuration directement auprès
  de `slurmctld` (`--conf-server`) - pas de `slurm.conf` partagé, pas de NFS.
- **Authentification `auth/slurm`** : clé partagée `slurm.key` dans un Secret,
  distribuée aux pods. **Pas de MUNGE.** Un `jwt.key` séparé sert au REST.
- **Scaling** d'un NodeSet : `StatefulSet` (replicas fixes, noms stables -
  retenu ici) ou `DaemonSet` (un pod par nœud éligible).

## 2. Réseau et services

Slinky crée un **headless service unique pour tous les workers du cluster**
(`slurm-workers-<controller>`) : les pods y adhèrent, leurs noms d'hôtes
Slurm sont résolus par le DNS Kubernetes. C'est ce qui permet le **callback
TCP des workers Julia** vers le driver (§4).

```mermaid
flowchart LR
    subgraph pods["pods (namespace slurm)"]
        PL["pod login"]
        PC["pod slurmctld"]
        PW0["pod worker-0"]
        PW1["pod worker-1"]
    end

    SVC1["svc slurm-controller<br/>:6817"]
    SVC2["svc slurm-workers (headless)<br/>:6818 - DNS de chaque pod"]
    SVC3["svc slurm-login-julia<br/>LoadBalancer (SSH, option)"]

    PL --- SVC3
    PC --- SVC1
    PW0 --- SVC2
    PW1 --- SVC2

    PC <-->|"configless --conf-server<br/>slurmctld ↔ slurmd :6818"| PW0
    PC <--> PW1
    PW0 <-->|"steps Slurm + callback TCP Julia"| PW1
```

| Port | Usage |
|---|---|
| 6817 | `slurmctld` (ordonnanceur) |
| 6818 | `slurmd` (démon de calcul) |
| 6820 | `slurmrestd` (si RestAPI déployée) |

## 3. Où vit le driver Julia ?

`SlurmClusterManager.jl` impose un contrat strict : `SlurmManager()` est
construit **dans une allocation Slurm existante** (`SLURM_JOB_ID` et
`SLURM_NTASKS` requis). Le driver Julia est donc **la tâche 0 d'un job**,
exécutée dans un pod de calcul - jamais un pod « libre » du cluster.

```mermaid
flowchart TB
    J["job Slurm : sbatch -N2 --ntasks=16"]
    J --> T0["tâche 0 (pod worker-0)<br/>DRIVER julia<br/>addprocs(SlurmManager())"]
    J --> T1["tâches 1-8 (pod worker-0)<br/>workers julia --worker"]
    J --> T9["tâches 9-16 (pod worker-1)<br/>workers julia --worker"]
    T0 -->|"srun (step dédié)"| T1
    T0 -->|"srun (step dédié)"| T9
    T1 -->|"TCP host:port<br/>(DNS pod)"| T0
    T9 -->|"TCP host:port<br/>(DNS pod)"| T0
```

## 4. Flux complet d'un job Julia

```mermaid
sequenceDiagram
    autonumber
    actor U as Utilisateur
    participant LP as Pod login (client Slurm)
    participant CT as slurmctld (pod Controller)
    participant W0 as pod worker-0 (slurmd)
    participant D as Driver julia (tâche 0)
    participant W as Workers julia --worker

    U->>LP: sbatch julia_pi.sbatch
    LP->>CT: RPC soumission (auth/slurm)
    CT->>W0: allocation 16 tâches (2 nœuds)
    W0->>D: lancement script batch → julia 02_monte_carlo_pi.jl
    D->>D: addprocs(SlurmManager())
    D->>CT: srun --ntasks=16 ... julia --worker (step)
    CT->>W0: step 16 tâches
    CT->>W0: (tâches sur worker-1 aussi)
    W0-->>D: workers : "port#host" imprimés sur stdout srun
    W-->>D: connexion TCP vers host:port du driver + cookie (stdin)
    D-->>D: cluster Distributed prêt (nworkers() == 16)
    Note over D,W: pmap / @distributed exécutés sur les workers
    D->>CT: rmprocs + fin de job
```

Détails du mécanisme `addprocs` : [05 - Julia Distributed](05-julia-distributed-slurm.md).

## 5. Limites du modèle (à connaître)

- **Pas de filesystem partagé** par défaut : le code et l'environnement Julia
  vivent **dans l'image** (voir [04](04-images-conteneurs.md)) ; les données
  massives exigent un volume réseau (PVC RWX, NFS…) monté sur les NodeSets.
- **Sortie sbatch locale** : `--output=/tmp/slurm-%j.out` atterrit sur le pod
  de calcul ; récupération par `kubectl exec` (voir
  [06 - Soumission de jobs](06-soumission-jobs.md)).
- **1 pod = 1 nœud Slurm** : les jobs utilisent les CPU/RAM demandés dans les
  `resources` du NodeSet ; surveillez les requests/limits.

→ Suivant : [02 - Prérequis & installation](02-prerequis-installation.md)
