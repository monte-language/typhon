{ pkgs, monte }:
pkgs.stdenv.mkDerivation {
  name = "mast-capnproto";

  src = pkgs.capnproto.src;
  sourceRoot = "capnproto-c++-0.7.0/src";

  buildInputs = [ pkgs.capnproto monte ];

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/capn/compat/
    for module in rpc rpc-twoparty schema persistent compat/json; do
      capnpc -o monte capnp/$module.capnp > $out/capn/$module.mast
    done
  '';
}
