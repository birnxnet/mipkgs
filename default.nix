# Non-flake entry point: `nix-build -A <pkg>`, and what nix-update uses
# (its flake mode trips over lazily-copied flake sources).
# Uses the same nixpkgs revision as flake.lock.
{system ? builtins.currentSystem}: let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  n = lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  nixpkgs = fetchTarball {
    url = "https://github.com/${n.owner}/${n.repo}/archive/${n.rev}.tar.gz";
    sha256 = n.narHash;
  };
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
in
  pkgs.callPackage ./pkgs {}
