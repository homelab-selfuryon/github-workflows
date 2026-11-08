# CLAUDE.md

Reusable workflows (`on: workflow_call`) of the `homelab-selfuryon` org. Read `meta/delivery.md`
(contract), `meta/github-workflows.md` (card) and `meta/security-baseline.md` first.

## Layout

```
.github/workflows/   the reusable workflows + ci.yaml, release.yaml, update.yaml (this repository's own)
.github/chainguard/  octo-sts policies for release-please and devenv-update on this repository
.github/renovate.json
devenv.nix, devenv.yaml, devenv.lock   actionlint, zizmor, shellcheck, cue; treefmt + git hooks
```

## Commands

```
devenv test                                   # treefmt, actionlint, zizmor (offline)
devenv shell -- actionlint
GH_TOKEN=$(gh auth token) devenv shell -- zizmor .github/workflows    # online audits
```

## Conventions

- Every action pinned by full SHA with a `# vX.Y.Z` comment; top-level `permissions: {}`, minimal
  per-job permissions; no `${{ }}` inside `run:` (use `env:`); no `pull_request_target`/`workflow_run`.
- No inputs unless unavoidable; validate everything attacker-influenced (PR number, tag, names) with
  a regex before use.
- Repository commands go through the caller's devenv (`devenv shell -- <cmd>`); cosign and oras come
  from the pinned setup actions. `DEVENV_VERSION` is repeated in each workflow: change all together.
- Flux-verified artifacts (gitops, platform sets) are signed in the publishing repository's own job, never here.
- Signing jobs: `id-token: write`, keyless cosign by digest. The identity (workflow file name) is part
  of the contract: renaming a workflow breaks every verifier.
- The final required check job is called `final-check` (no `name:`).
- Conventional Commits (`!` for breaking changes), signed commits.
