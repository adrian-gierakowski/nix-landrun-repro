{
  description = "Nix 2.35 impure evaluation regression under Landlock";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/d3b13ad75cc492690728f9307e443dec9ef9a20e";

  outputs =
    { nixpkgs, ... }:
    let
      forSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      packages = forSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          landlockProbe = pkgs.runCommandCC "landlock-probe" { } ''
            mkdir -p "$out/bin"
            $CC -Wall -Wextra -Werror ${./landlock-probe.c} -o "$out/bin/landlock-probe"
          '';
          runner =
            name: nix: body:
            pkgs.writeShellApplication {
              inherit name;
              runtimeInputs = [
                pkgs.coreutils
                pkgs.landrun
              ];
              text = ''
                ${landlockProbe}/bin/landlock-probe
                work=$(mktemp -d)
                trap 'rm -rf "$work"' EXIT
                mkdir "$work/allowed"
                sandbox=(
                  landrun --best-effort
                  --rox /nix/store --ro /proc --rw /dev/null --rw "$work/allowed"
                  --env "HOME=$work/allowed" --env "NIX_CONF_DIR=$work/allowed"
                  --env NIX_USER_CONF_FILES=/dev/null
                )
                "''${sandbox[@]}" -- ${landlockProbe}/bin/landlock-probe --check-denied
                evaluate() {
                  "''${sandbox[@]}" -- ${nix}/bin/nix --store dummy:// \
                    --extra-experimental-features nix-command eval "$@"
                }
                ${nix}/bin/nix --version
                ${body}
              '';
            };
          reproduce =
            name: nix:
            runner name nix ''
              echo 'Pure evaluation (expected: 2):'
              evaluate --expr '1 + 1'
              echo 'Impure evaluation:'
              evaluate --impure --expr '1 + 1'
            '';
        in
        rec {
          repro = reproduce "nix-landrun-repro" pkgs.nixVersions.nix_2_35;
          control = reproduce "nix-landrun-control" pkgs.nixVersions.nix_2_34;
          landlock-probe = landlockProbe;
          default = repro;
        }
      );
    };
}
