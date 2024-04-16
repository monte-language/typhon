{ pkgs, rpypkgs }:
let
  lib = pkgs.lib;
  vmSrc = let loc = part: (toString ./..) + part;
   in builtins.filterSource (path: type:
    let p = toString path;
     in (lib.hasPrefix (loc "/typhon/") p &&
         (type == "directory" || lib.hasSuffix ".py" p)) ||
      p == loc "/typhon" ||
      p == loc "/main.py") ./..;
  typhon = with pkgs; rec {
    # Want to build Typhon with Clang instead of GCC?
    # Add `stdenv = pkgs.clangStdenv` to either VM. ~ C.
    typhonVm = callPackage ./vm.nix {
      inherit vmSrc rpypkgs; buildJIT = false;
    };
    typhonVmJIT = callPackage ./vm.nix {
      inherit vmSrc rpypkgs; buildJIT = true;
    };
    mast = callPackage ./mast.nix { typhonVm = typhonVmJIT;
                                    pkgs = pkgs; };

    typhonDumpMAST = callPackage ./dump.nix {};
    # XXX broken for unknown reasons
    # bench = callPackage ./bench.nix { typhonVm = typhonVmJIT; mast = mast; }
    monte = callPackage ./monte-script.nix {
      typhonVm = typhonVmJIT; mast = mast;
    };
    capnMast = callPackage ./capn.nix { inherit pkgs monte; };
    fullMast = pkgs.symlinkJoin {
      name = "mast-full";
      paths = [ mast capnMast ];
    };
    fullMonte = callPackage ./monte-script.nix {
      typhonVm = typhonVmJIT; mast = fullMast;
    };
    mtBusybox = monte.override { shellForMt = "${pkgs.busybox}/bin/sh"; };
    mtLite = mtBusybox.override { withBuild = false; };
  };
  typhonDocker = {
    mtDocker = pkgs.dockerTools.buildImage {
        name = "monte-dev";
        tag = "latest";
        contents = [pkgs.nix.out pkgs.busybox typhon.mtBusybox typhon.typhonVmJIT];
        runAsRoot = ''
          #!${pkgs.busybox}/bin/sh
          mkdir -p /etc
          tee /etc/profile <<'EOF'
          echo "Try \`monte repl' for an interactive Monte prompt."
          echo "See \`monte --help' for more commands."
          EOF
        '';
        config = {
            Cmd = [ "${pkgs.busybox}/bin/sh" "-l" ];
            WorkingDir = "/";
            };
        };
    mtLiteDocker = pkgs.dockerTools.buildImage {
        name = "repl";
        tag = "latest";
        contents = with typhon; [mtLite typhonVmJIT];
        config = {
            Cmd = [ "/bin/monte" "repl" ];
            WorkingDir = "/";
            };
        };
    };
in
  typhon
