# docs/make.jl — build de la documentation (Documenter.jl → GitHub Pages)
#
#   Local :  julia --project=docs -e 'using Pkg; Pkg.instantiate()'
#            julia --project=docs docs/make.jl
#            → site statique dans docs/build/ (ouvrir docs/build/index.html)
#
#   CI/CD :  .github/workflows/Documentation.yml
#            makedocs -> deploydocs : le site compilé est poussé sur la branche
#            `gh-pages` (jamais `main`). GitHub Pages « Deploy from a branch »
#            -> gh-pages / (root). Commits gh-pages signés « Documenter.jl »,
#            hors branche par défaut -> n'apparaissent pas dans les contributeurs.

using Documenter
using Literate

const REPO_URL   = "https://github.com/deep75/julia-slurm-k8s"
const EXAMPLES   = joinpath(@__DIR__, "..", "julia")
const GENERATED  = joinpath(@__DIR__, "src", "exemples")

# --- Exemples : julia/*.jl -> pages Documenter via Literate (sans exécution) ---
# Les scripts restent exécutables tels quels ; ici ils sont seulement mis en forme
# (prose issue des commentaires + code). Aucune exécution : ils exigent une
# allocation Slurm.
const EXAMPLE_PAGES = [
    "01_hello_distributed" => "01 — Hello Distributed",
    "02_monte_carlo_pi"    => "02 — Monte-Carlo π",
    "03_pmap_eigen"        => "03 — pmap & LinearAlgebra",
    "04_options_demo"      => "04 — Options d'addprocs",
]

"Supprime les filets de bannière et impose un titre H1 propre."
literate_preprocess(title) = content -> begin
    kept = filter(split(content, '\n')) do line
        !occursin(r"^#[ \t]*[=\-–—_]{4,}[ \t]*$", line)
    end
    string("# # ", title, "\n#\n", join(kept, '\n'))
end

isdir(GENERATED) && rm(GENERATED; recursive = true)
mkpath(GENERATED)
for (base, title) in EXAMPLE_PAGES
    Literate.markdown(
        joinpath(EXAMPLES, base * ".jl"), GENERATED;
        name       = base,
        preprocess = literate_preprocess(title),
        codefence  = "```julia" => "```",   # blocs simples : pas d'exécution Documenter
        repo_root_url = REPO_URL * "/blob/main",
        documenter = true,
        credit     = true,
    )
end

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
        assets            = ["assets/mermaid.bundle.js", "assets/mermaid.js"],
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
        "Exemples de code"                 => ["exemples/$b.md" for (b, _) in EXAMPLE_PAGES],
    ],
)

deploydocs(;
    repo      = "github.com/deep75/julia-slurm-k8s.git",
    devbranch = "main",
    versions  = ["dev" => "dev"],
)
