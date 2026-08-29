# docs/make.jl — build de la documentation (Documenter.jl → GitHub Pages)
#
#   Local :  julia --project=docs -e 'using Pkg; Pkg.instantiate()'
#            julia --project=docs docs/make.jl
#            → site statique dans docs/build/ (ouvrir docs/build/index.html)
#
#   CI/CD :  .github/workflows/Documentation.yml
#            makedocs → docs/build/ → actions/upload-pages-artifact
#                                   → actions/deploy-pages
#            GitHub Pages « Source : GitHub Actions » — aucune branche gh-pages,
#            aucun token long ; déploiement OIDC via l'environnement github-pages.

using Documenter

makedocs(;
    sitename = "Julia + Slurm sur Kubernetes — Slinky × SlurmClusterManager",
    authors  = "deep75",
    repo     = Remotes.GitHub("deep75", "julia-slurm-k8s"),
    format   = Documenter.HTML(;
        lang              = "fr",
        prettyurls        = get(ENV, "CI", "false") == "true",
        canonical         = "https://deep75.github.io/julia-slurm-k8s",
        edit_link         = "main",
        inventory_version = "",
        # Rendu Mermaid maison (contourne le conflit RequireJS/AMD).
        assets            = ["assets/mermaid.js"],
    ),
    pages = [
        "Accueil"                          => "index.md",
        "01 — Architecture"                => "01-architecture.md",
        "02 — Prérequis & installation"    => "02-prerequis-installation.md",
        "03 — Déploiement du cluster Slurm" => "03-deploiement-slurm.md",
        "04 — Images conteneurs"           => "04-images-conteneurs.md",
        "05 — Julia Distributed sur Slurm" => "05-julia-distributed-slurm.md",
        "06 — Soumission de jobs"          => "06-soumission-jobs.md",
        "07 — Exemples bout-en-bout"       => "07-exemples-bout-en-bout.md",
        "08 — Troubleshooting"             => "08-troubleshooting.md",
    ],
)
