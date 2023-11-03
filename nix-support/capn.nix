{ pkgs, monte }:
pkgs.stdenv.mkDerivation {
  name = "mast-capnproto";

  srcs = [ pkgs.capnproto.src ../mast/capn ];
  sourceRoot = "capnproto-c++-0.9.0/src";

  # XXX hack: Compile our value schema specially; it's the only Capn schema
  # that we ship, and this is the best time to build it.
  postUnpack = ''
    read -a srcArray <<< "$srcs"
    cp ''${srcArray[1]}/montevalue.capnp $sourceRoot/
  '';

  buildInputs = [ pkgs.capnproto monte ];

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/capn/compat/
    for module in rpc rpc-twoparty schema persistent compat/json; do
      capnpc -o monte capnp/$module.capnp > $out/capn/$module.mast
    done
    capnpc -o monte montevalue.capnp > $out/capn/montevalue.mast
  '';
}
