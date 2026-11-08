{ pkgs, ... }:
let
  # CUE v0.18.0-rc.3 from the upstream release tarball (a static binary).
  # Drop this and use pkgs.cue once nixpkgs ships v0.18.
  cue =
    let
      version = "0.18.0-rc.3";
      assets = {
        "x86_64-linux" = {
          arch = "linux_amd64";
          hash = "sha256-krWMjj9th0vHRt4uve2boMaSRgYfxjYmbbRZ6fL6W50=";
        };
        "aarch64-linux" = {
          arch = "linux_arm64";
          hash = "sha256-KRz7DtQhfSEi4i93UNJ6svGn848TPuts+TqIuiLFbsM=";
        };
        "x86_64-darwin" = {
          arch = "darwin_amd64";
          hash = "sha256-2n3fqRcuusNsFV9kkw4D1+6y9vhWqozcYTvT1Emu5YI=";
        };
        "aarch64-darwin" = {
          arch = "darwin_arm64";
          hash = "sha256-GQ4UtoKKM02q7QmJ17Eo6A2yAlUj7ADdwfKMlv9IZt4=";
        };
      };
      asset = assets.${pkgs.stdenv.hostPlatform.system} or (throw "cue: unsupported system");
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "cue";
      inherit version;
      src = pkgs.fetchurl {
        url = "https://github.com/cue-lang/cue/releases/download/v${version}/cue_v${version}_${asset.arch}.tar.gz";
        inherit (asset) hash;
      };
      sourceRoot = ".";
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 cue "$out/bin/cue"
        runHook postInstall
      '';
      meta.mainProgram = "cue";
    };
in
{
  packages = [
    cue
  ]
  ++ (with pkgs; [
    actionlint
    shellcheck
    zizmor
    jq
    yq-go
  ]);

  treefmt = {
    enable = true;
    config.programs.nixfmt.enable = true;
    config.settings.global.excludes = [ "devenv.lock" ];
  };

  git-hooks.hooks = {
    treefmt.enable = true;
    actionlint.enable = true;
  };

  # `devenv test`
  enterTest = ''
    set -euo pipefail
    actionlint
    zizmor --offline .github/workflows
  '';
}
