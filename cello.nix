{ nixpkgs ? import <nixpkgs> {} }:
let
  inherit (nixpkgs) pkgs;
  monte = (import ./default.nix {}).monte;
in pkgs.stdenv.mkDerivation {
  name = "cello-test";
  src = ./.;
  buildInputs = with pkgs; [ libcello ];
  buildPhase = ''
    ${monte}/bin/monte eval cello.mt | tee test.c
    gcc -std=gnu99 test.c monte.c -lCello -lpthread -o test
  '';
  installPhase = ''
    mv test $out
  '';
}
