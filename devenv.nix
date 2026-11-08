# Only what is specific to github-workflows. CUE, treefmt, the base git hooks and
# actionlint/zizmor/shellcheck/jq come from platform-kit/devenv/cue.nix (see devenv.yaml).
{ pkgs, ... }:
{
  packages = [ pkgs.yq-go ];

  git-hooks.hooks.actionlint.enable = true;

  # release-please writes CHANGELOG.md; formatting it would fight every release.
  # (Moves into platform-kit base.nix with v0.1.1.)
  treefmt.config.settings.global.excludes = [ "CHANGELOG.md" ];

  # `devenv test` (after the base step `treefmt --fail-on-change`)
  enterTest = ''
    actionlint
    zizmor --offline .github/workflows
  '';
}
