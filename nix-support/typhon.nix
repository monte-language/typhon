{ system ? builtins.currentSystem }:
let
  nixpkgs = import <nixpkgs> { inherit system; };
  lib = nixpkgs.lib;
  libsodium0 = nixpkgs.libsodium.overrideDerivation (oldAttrs: {stripAllList = "lib";});
  vmSrc = let loc = part: (toString ./..) + part;
   in builtins.filterSource (path: type:
    let p = toString path;
     in (lib.hasPrefix (loc "/typhon/") p &&
         (type == "directory" || lib.hasSuffix ".py" p)) ||
      p == loc "/typhon" ||
      p == loc "/main.py") ./..;
  mastSrc = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      let p = toString path;
       in ((lib.hasPrefix (loc "/mast/") p &&
            (type == "directory" || lib.hasSuffix ".mt" p || lib.hasSuffix ".mt.md" p)) ||
           (lib.hasPrefix (loc "/boot/") p &&
            (type == "directory" || lib.hasSuffix ".ty" p || lib.hasSuffix ".mast" p)) ||
        p == loc "/mast" ||
        p == loc "/boot" ||
        p == loc "/Makefile" ||
        p == loc "/lit.sh" ||
        p == loc "/loader.mast" ||
        p == loc "/lit.sh" ||
        p == loc "/repl.mast")) ./..;
  pypy = nixpkgs.pypy.override { packageOverrides = (s: su: {
    mock = su.mock.overridePythonAttrs (old: { doCheck = false; });
    pytest = su.pytest.overridePythonAttrs (old: { doCheck = false; });
  }); };
  vmConfig = {
    inherit vmSrc pypy ;
    pypyPackages = pypy.pkgs;
    libsodium = libsodium0;
    # Want to build Typhon with Clang instead of GCC? Uncomment this next
    # line. ~ C.
    # stdenv = nixpkgs.clangStdenv;
  };
  typhon = with nixpkgs; rec {
    typhonVm = callPackage ./vm.nix (vmConfig // { buildJIT = false; });
    typhonVmJIT = callPackage ./vm.nix (vmConfig // { buildJIT = true; });
    mast = callPackage ./mast.nix { mastSrc = mastSrc;
                                    typhonVm = typhonVmJIT;
                                    pkgs = nixpkgs; };

    typhonDumpMAST = callPackage ./dump.nix {};
    # XXX broken for unknown reasons
    # bench = callPackage ./bench.nix { typhonVm = typhonVmJIT; mast = mast; }
    monte = callPackage ./monte-script.nix {
      typhonVm = typhonVmJIT; mast = mast;
    };
    mtBusybox = monte.override { shellForMt = "${nixpkgs.busybox}/bin/sh"; };
    mtLite = mtBusybox.override { withBuild = false; };
    mtDocker = nixpkgs.dockerTools.buildImage {
        name = "monte-dev";
        tag = "latest";
        contents = [nixpkgs.nix.out nixpkgs.busybox mtBusybox typhonVmJIT];
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
        contents = [mtLite typhonVmJIT];
        config = {
            Cmd = [ "/bin/monte" "repl" ];
            WorkingDir = "/";
            };
        };
    };
in
  typhon
