{ system ? builtins.currentSystem, vmSrc, mastSrc }:
let
  nixpkgs = import <nixpkgs> { inherit system; };
  libsodium0 = nixpkgs.libsodium.overrideDerivation (oldAttrs: {stripAllList = "lib";});
  typhon = with nixpkgs; rec {
    typhonVm = callPackage ./vm.nix { vmSrc = vmSrc;
                                      buildJIT = false;
                                      libsodium = libsodium0; };
    typhonVmJIT = callPackage ./vm.nix { buildJIT = true;
                                         vmSrc = vmSrc;
                                         libsodium = libsodium0; };
    mast = callPackage ./mast.nix { mastSrc = mastSrc;
                                    typhonVm = typhonVm; };
    typhonDumpMAST = callPackage ./dump.nix {};
    # XXX broken for unknown reasons
    # bench = callPackage ./bench.nix { typhonVm = typhonVm; mast = mast; }
    montePackage = callPackage ./montePackage.nix { typhonVm = typhonVm; mast = mast; };
    monteDockerPackage = lockSet: pkgs.dockerTools.buildImage {
              name = lockSet.mainPackage;
              tag = "latest";
              contents = typhon.montePackage lockSet;
              config = {
                Cmd = [ ("/bin/" + lockSet.packages.${lockSet.mainPackage}.entrypoint) ];
                WorkingDir = "";
              };
            };
    monte = callPackage ./monte-script.nix { typhonVm = typhonVm; mast = mast;
                                vmSrc = vmSrc; mastSrc = mastSrc; };
    mtBusybox = monte.override { shellForMt = "${nixpkgs.busybox}/bin/sh"; };
    mtLite = mtBusybox.override { withBuild = false; };
    mtDocker = nixpkgs.dockerTools.buildImage {
        name = "monte-dev";
        tag = "latest";
        contents = [nixpkgs.nix.out nixpkgs.busybox mtBusybox typhonVm];
        runAsRoot = ''
          #!${nixpkgs.busybox}/bin/sh
          mkdir -p /etc
          tee /etc/profile <<'EOF'
          echo "Try \`monte repl' for an interactive Monte prompt."
          echo "See \`monte --help' for more commands."
          EOF
        '';
        config = {
            Cmd = [ "${nixpkgs.busybox}/bin/sh" "-l" ];
            WorkingDir = "/";
            };
        };
    mtLiteDocker = nixpkgs.dockerTools.buildImage {
        name = "repl";
        tag = "latest";
        contents = [mtLite typhonVm];
        config = {
            Cmd = [ "/bin/monte" "repl" ];
            WorkingDir = "/";
            };
        };
    };
in
  typhon
