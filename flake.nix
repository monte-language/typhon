{
  description = "A virtual machine and standard library for Monte";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";
    rpypkgs = {
      url = "git://git.pf.osdn.net/gitroot/c/co/corbin/rpypkgs.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, rpypkgs }:
    let
      noPythonCheck = p: p.overridePythonAttrs (old: {
        doCheck = false;
      });
      overlay = final: prev: {
        libsodium = prev.libsodium.overrideDerivation (oldAttrs: {
          stripAllList = "lib";
        });
        pypy = prev.pypy.override {
          packageOverrides = (s: su: {
            mock = noPythonCheck su.mock;
            pytest = noPythonCheck su.pytest;
          });
        };
      };
    in flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowBroken = true;
            permittedInsecurePackages = [
              "python-2.7.18.6"
            ];
          };
          overlays = [ overlay ];
        };
        typhon = import ./nix-support/typhon.nix { inherit pkgs rpypkgs; };
        qbe = pkgs.stdenv.mkDerivation {
          name = "qbe-unstable";

          src = pkgs.fetchgit {
            url = "git://c9x.me/qbe.git";
            sha256 = "0r2af5036bbqwd3all6q0mlwrjcww4xgi1yr8l5xgddmx6711ygw";
          };

          makeFlags = [ "PREFIX=$(out)" ];
          doCheck = true;
        };
      in {
        overlays.default = overlay;
        packages = typhon // {
          default = typhon.monte;
        };
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ cachix nix-tree ];
        };
      }
    );
}
