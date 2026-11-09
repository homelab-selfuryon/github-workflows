# github-workflows

Reusable GitHub Actions workflows of [`homelab-selfuryon`](https://github.com/homelab-selfuryon).
Every repository in the org calls these instead of writing its own release logic. Checks that only one repository needs (gitops verify, components check) and the publishers Flux verifies live in that repository.

The signing identity of every _app_ artifact (image, manifests) is one of these workflows
(`.../github-workflows/.github/workflows/<name>.yaml@<ref>`, source repository and tag in the certificate).
`gitops`'s verify check and Kyverno accept only those, so a product repository cannot sign something the platform
trusts by itself. Artifacts _Flux_ verifies (`gitops/<cluster>`, platform sets) are the exception: they are
signed in a job defined in the publishing repository itself (`gitops/.github/workflows/publish.yaml`,
`platform-components/.github/workflows/release.yaml`, both `@refs/heads/main`), because Flux matches
only the certificate subject and a reusable workflow would put `github-workflows` there, letting a
workflow on any branch produce an accepted artifact; there is no reusable workflow for those two. For app
artifacts the logic lives here for the same reason it is
called pinned (Renovate bumps the SHA): release logic stays out of the product repository.

| Workflow              | Called by                                             | Does                                                                                                                             |
| --------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `rust-ci.yaml`        | app, PR and main                                      | `devenv test`, `cue vet ./deploy`                                                                                                |
| `app-preview.yaml`    | app, PR (same repository only)                        | image `pr-<n>-<sha7>`, `manifests:pr-<n>`, both cosign signed                                                                    |
| `app-release.yaml`    | app, tag `v*`, environment `staging`                  | image (buildx, SBOM + provenance), `manifests:<version>` (staging + prod), signed, PR to `gitops` `staging.json` with auto-merge |
| `app-promote.yaml`    | app, `workflow_dispatch` on a tag, environment `prod` | resolve and verify `manifests:<tag>`, PR to `gitops` `prod.json` (team approves)                                                 |
| `app-register.yaml`   | app, main                                             | first run after the template rename: PR to `gitops` registering the app                                                          |
| `release-please.yaml` | app, main                                             | release PR and tag, token from octo-sts                                                                                          |
| `devenv-update.yaml`  | any repository, weekly                                | `devenv update` as a PR (replaces Renovate for `devenv.lock`)                                                                    |
| `lint-workflows.yaml` | everyone                                              | zizmor, actionlint                                                                                                               |

Contracts (names, artifacts, identities, the commands called in each repository):
`meta/delivery.md`.

## Calling a workflow

A caller grants the permissions the reusable job needs (a reusable workflow can never have more
than its caller gives it) and passes nothing else: none of these workflows has inputs. They read
everything from the repository they run in and validate it (app name = repository name, tag is
a semantic version, digests and names match strict regexes) before it reaches a command or a PR.

```yaml
# .github/workflows/release.yaml in an app
on:
  push:
    tags: ["v*"]
permissions: {}
jobs:
  release:
    permissions:
      contents: read
      packages: write
      id-token: write
    # Renovate pins this to a SHA after the first release.
    uses: homelab-selfuryon/github-workflows/.github/workflows/app-release.yaml@v1.0.0
```

Per-workflow permissions are listed at the top of each file. The app repository needs the
GitHub Environments `staging` and `prod` (deployment rule: tags `v*`), octo-sts trust policies in its
`.github/chainguard/` (below), and its packages must be public (CUE and Flux read them without
credentials; `GITHUB_TOKEN` is used where a login is needed). The repository's custom property `kind`
is `app` (platform-terraform sets it); gitops' trust policies require it.

## Where the tools come from

- **Repository commands** run through the caller's devenv: `devenv test`, `devenv shell -- cue ...`
  (components, gitops and apps use their own `devenv.nix`; `lint-workflows` expects actionlint
  and zizmor in it). The runner gets Nix (`cachix/install-nix-action`), the public devenv cache
  (`cachix/cachix-action`, read-only, no token) and devenv itself (`DEVENV_VERSION` in each
  workflow).
- **Release-only tools** that are none of the caller's business, cosign and oras, come from pinned
  official setup actions (`sigstore/cosign-installer`, `oras-project/setup-oras`), so Renovate bumps
  them. Docker (buildx) comes from the runner and `docker/setup-buildx-action`.
- **Images** are built from the caller's `Containerfile` with `docker/build-push-action`
  (`provenance: mode=max`, `sbom: true`), pushed by tag, and the digest of the resulting image
  index is cosign signed. SBOM and provenance live in that index, so the signature covers them;
  `actions/attest-build-provenance` is not used because it would add a second, unverified statement
  of the same build by the same job.
- OCI manifest artifacts are one deterministic `tar.gz` layer of media type
  `application/vnd.oci.image.layer.v1.tar+gzip`, pushed with `oras`, signed by digest with keyless cosign.
- Cross-repository PRs use short-lived octo-sts tokens (scope `homelab-selfuryon/gitops`, identities
  `app-release`, `app-promote`, `app-register`, `components-release`; the policies are
  in `gitops/.github/chainguard/`). Commits are made through `create-pull-request` with
  `sign-commits`, credentials are never persisted.

## Trust policies in the caller

Scope = the caller's own repository, so these live in the caller's `.github/chainguard/`:

```yaml
# devenv-update.sts.yaml (any repository; `release-please.sts.yaml` is the same with the other workflow)
issuer: https://token.actions.githubusercontent.com
subject_pattern: repo:homelab-selfuryon@353728095/<repo>@[0-9]+:ref:refs/heads/main
claim_pattern:
  event_name: schedule|workflow_dispatch
  job_workflow_ref: homelab-selfuryon/github-workflows/\.github/workflows/devenv-update\.yaml@.+
permissions:
  contents: write
  pull_requests: write
```

```yaml
# release-please.sts.yaml
issuer: https://token.actions.githubusercontent.com
subject_pattern: repo:homelab-selfuryon@353728095/<repo>@[0-9]+:ref:refs/heads/main
claim_pattern:
  job_workflow_ref: homelab-selfuryon/github-workflows/\.github/workflows/release-please\.yaml@.+
permissions:
  contents: write
  pull_requests: write
```

The caller of `devenv-update.yaml` (weekly):

```yaml
on:
  schedule: [{ cron: "0 6 * * 1" }]
  workflow_dispatch:
permissions: {}
jobs:
  devenv:
    permissions: { contents: read, id-token: write }
    uses: homelab-selfuryon/github-workflows/.github/workflows/devenv-update.yaml@v1.0.0
```

## Developing

`devenv shell` (direnv: `.envrc`) gives actionlint, zizmor, shellcheck, cue (v0.18.0-rc.3 from the
upstream tarball). `devenv test` runs treefmt, actionlint and zizmor. `devenv.lock` is updated weekly
by `update.yaml` (this repository calls its own `devenv-update.yaml`). Renovate config is
`.github/renovate.json`. Release: release-please opens a release PR from Conventional Commits
(`!` for breaking changes); the tag `v1.x.y` is what callers pin.
