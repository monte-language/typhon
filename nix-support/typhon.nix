{ system ? builtins.currentSystem, bakedVmSrc ? null, bakedMastSrc ? null }:
let
  nixpkgs = import <nixpkgs> { inherit system; };
  lib = nixpkgs.lib;
  libsodium0 = nixpkgs.libsodium.overrideDerivation (oldAttrs: {stripAllList = "lib";});
  vmSrc = if (bakedVmSrc != null) then bakedVmSrc else
    let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      let p = toString path;
       in (lib.hasPrefix (loc "/typhon/") p &&
           (type == "directory" || lib.hasSuffix ".py" p)) ||
        p == loc "/typhon" ||
        p == loc "/main.py") ./..;
  mastSrc = if (bakedMastSrc != null) then bakedMastSrc else
    let loc = part: (toString ./..) + part;
       in builtins.filterSource (path: type:
        let p = toString path;
         in ((lib.hasPrefix (loc "/mast/") p &&
              (type == "directory" || lib.hasSuffix ".mt" p)) ||
             (lib.hasPrefix (loc "/boot/") p &&
              (type == "directory" || lib.hasSuffix ".ty" p || lib.hasSuffix ".mast" p)) ||
          p == loc "/mast" ||
          p == loc "/boot" ||
          p == loc "/Makefile" ||
          p == loc "/loader.mast" ||
          p == loc "/repl.mast")) ./..;
  typhon = with nixpkgs; rec {
    typhonVm = callPackage ./vm.nix { vmSrc = vmSrc;
                                      buildJIT = false;
                                      libsodium = libsodium0; };
    typhonVmCrashy = callPackage ./vm.nix { buildJIT = true;
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
            Cmd = [ "${nixpkgs.busybox}/bin/sh" ];
            WorkingDir = "/";
            };
        };
    mtLiteDocker = nixpkgs.dockerTools.buildImage {
        name = "repl";
        tag = "latest";
        contents = [monteLite typhonVm];
        config = {
            Cmd = [ "/bin/monte" "repl" ];
            WorkingDir = "/";
            };
        };
    };
in
  typhon
