{ system ? builtins.currentSystem }:
let
  nixball = builtins.fetchTarball {
    name = "typhon-pinned-nixpkgs";
    url = https://github.com/NixOS/nixpkgs/archive/ab5863afada3c1b50fc43bf774b75ea71b287cde.tar.gz;
    sha256 = "1iv5xmklasnv3cyhz4nbjd49kgyxcmg815p0ab817fy49nn8js7f";
  };
  nixpkgs = import nixball { inherit system; };
  lib = nixpkgs.lib;
  libsodium0 = nixpkgs.libsodium.overrideDerivation (oldAttrs: {stripAllList = "lib";});
  vmSrc = let loc = part: (toString ./..) + part;
   in builtins.filterSource (path: type:
    let p = toString path;
     in (lib.hasPrefix (loc "/typhon/") p &&
         (type == "directory" || lib.hasSuffix ".py" p)) ||
      p == loc "/typhon" ||
      p == loc "/main.py") ./..;
  pypy = nixpkgs.pypy.override {
    packageOverrides = (s: su: {
      mock = su.mock.overridePythonAttrs (old: { doCheck = false; });
      pytest = su.pytest.overridePythonAttrs (old: { doCheck = false; });
    });
  };
  vmConfig = {
    inherit vmSrc pypy;
    pypyPackages = pypy.pkgs;
    libsodium = libsodium0;
    # Want to build Typhon with Clang instead of GCC? Uncomment this next
    # line. ~ C.
    # stdenv = nixpkgs.clangStdenv;
  };
  typhon = with nixpkgs; rec {
    typhonVm = callPackage ./vm.nix (vmConfig // { buildJIT = false; });
    typhonVmJIT = callPackage ./vm.nix (vmConfig // { buildJIT = true; });
    mast = callPackage ./mast.nix { typhonVm = typhonVmJIT;
                                    pkgs = nixpkgs; };

    typhonDumpMAST = callPackage ./dump.nix {};
    # XXX broken for unknown reasons
    # bench = callPackage ./bench.nix { typhonVm = typhonVmJIT; mast = mast; }
    monte = callPackage ./monte-script.nix {
      typhonVm = typhonVmJIT; mast = mast;
    };
    capnMast = callPackage ./capn.nix {
      pkgs = nixpkgs; monte = monte;
    };
    fullMast = nixpkgs.symlinkJoin {
      name = "mast-full";
      paths = [ mast capnMast ];
    };
    fullMonte = callPackage ./monte-script.nix {
      typhonVm = typhonVmJIT; mast = fullMast;
    };
    mtBusybox = monte.override { shellForMt = "${nixpkgs.busybox}/bin/sh"; };
    mtLite = mtBusybox.override { withBuild = false; };
  };
  typhonDocker = {
    mtDocker = nixpkgs.dockerTools.buildImage {
        name = "monte-dev";
        tag = "latest";
        contents = [nixpkgs.nix.out nixpkgs.busybox typhon.mtBusybox typhon.typhonVmJIT];
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
        contents = with typhon; [mtLite typhonVmJIT];
        config = {
            Cmd = [ "/bin/monte" "repl" ];
            WorkingDir = "/";
            };
        };
    };
in
  typhon
