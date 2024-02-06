{
  description = "A virtual machine for Monte";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowBroken = true;
            permittedInsecurePackages = [
              "python-2.7.18.7"
            ];
          };
        };
        typhon = import ./nix-support/typhon.nix pkgs;
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
        packages = typhon // {
          default = typhon.fullMonte;
        };
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ cachix ];
        };
      }
    );
}
