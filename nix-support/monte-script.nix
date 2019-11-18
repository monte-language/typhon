{stdenv, pkgs, lib, python27, typhonVm, mast, nix, nix-prefetch-scripts,
 rlwrap, withBuild ? true, shellForMt ? pkgs.stdenv.shell }:
let
  mt-bake-py = pkgs.writeText "mt-bake.py" (
    (if withBuild then
      "FETCHERS = {'git': '${nix-prefetch-scripts + "/bin/nix-prefetch-git"}'}\n"
     else "") +
  builtins.readFile ./mt-bake.py.in);
  buildDoc = if withBuild then
  ''  build                 Builds the current package, symlinks output as 'result'.
    docker-build          Builds the current package, creates a Docker image.
  ''
  else "";
  buildFuncs = if withBuild then ''
      doBuild() {
        ${python27}/bin/python ${mt-bake-py} &&
        ${nix.out}/bin/nix-build -E '
          let
            nixpkgs = import <nixpkgs> { };
            lockSet = builtins.fromJSON (builtins.readFile ./mt-lock.json);
            montePackage = nixpkgs.callPackage @out@/nix-support/montePackage.nix {
              typhonVm = ${typhonVm};
              mast = ${mast};
            };
          in montePackage lockSet'
    }
    doDockerBuild() {
        ${python27}/bin/python ${mt-bake-py} &&
        ${nix.out}/bin/nix-build -E '
          let
            nixpkgs = import <nixpkgs> { };
            lockSet = builtins.fromJSON (builtins.readFile ./mt-lock.json);
            montePackage = nixpkgs.callPackage @out@/nix-support/montePackage.nix {
              typhonVm = ${typhonVm};
              mast = ${mast};
            };
          in nixpkgs.dockerTools.buildImage {
            name = lockSet.mainPackage;
            tag = "latest";
            contents = montePackage lockSet;
            config = {
              Cmd = [ ("/bin/" + lockSet.packages.''${lockSet.mainPackage}.entrypoint) ];
              WorkingDir = "";
            };
          }'
    }
  '' else "";
  buildCmds = if withBuild then ''
        build)
            doBuild
            ;;
        docker-build)
            doDockerBuild
            ;;
  '' else ''
        build|docker-build)
            echo "This Monte installation does not include package-building tools."
            ;;
  '';
  mt-script = pkgs.writeScript "monte" ''
    #!${shellForMt}
    OPERATION=$1
    usage() {
        cat <<EOF

    Usage: monte <command>
    Command list:
      repl                       Starts interactive prompt in current package.
      muffin <module> <mastname> Statically link a module into a MAST file.
      lint <filename>            Reads source file, reports syntax errors.
      eval <filename>            Execute the code in a single source file.
      format <filename>          Print a canonically-formatted version of source file.
      add <name> <url>           Add a dependency to this package.
      rm <name>                  Remove a dependency from this package.
      run <entrypoint>           Invokes an entrypoint in current package.
      test <entrypoint>          Collects and executes tests defined for entrypoint.
      bench <entrypoint>         Collects and executes benchmarks defined for entrypoint.
      dot <entrypoint>           Creates a .dot graph of dependencies.
      dump-mast <mastname>       Print the Kernel-Monte from a MAST file.
      ${buildDoc}

    EOF
        exit $1
    }
    ${buildFuncs}
    RLWRAP=${rlwrap}/bin/rlwrap
    case $OPERATION in
        ${buildCmds}
        repl)
            $RLWRAP ${typhonVm}/mt-typhon -l ${mast} \
              ${mast}/loader run tools/repl
            if [ $? == 1 ]; then
                echo "Due to a Docker bug, readline-style editing is not currently available in this REPL. Sorry."
                ${typhonVm}/mt-typhon -l ${mast} \
                  ${mast}/loader run tools/repl
            fi
            ;;
        muffin)
            shift
            ${typhonVm}/mt-typhon -l ${mast} \
              ${mast}/loader run tools/muffin "$@"
            ;;
        lint)
            shift
            ${typhonVm}/mt-typhon -l ${mast} ${mast}/loader \
                       run montec -lint -terse "$@"
            ;;
        run|test|bench|dot)
            shift
            DEST=$(doBuild)
            entrypoint=$1
            shift
            $DEST/bin/$entrypoint --$OPERATION "$@"
            ;;
        bake)
            SOURCE=$2
            if [[ -z $SOURCE ]]; then
                usage 1
            else
                DEST=''${3:-''${SOURCE%.mt.mast}}
                ${typhonVm}/mt-typhon -l ${mast} ${mast}/loader \
                           run montec -mix "$SOURCE" "$DEST"
            fi
            ;;
        eval)
            SOURCE=$2
            if [[ -z $SOURCE ]]; then
                usage 1
            else
                if [[ "$SOURCE" == *.mt ]]; then
                   MASTSOURCE=''${SOURCE%.mt}.mast
                   ${typhonVm}/mt-typhon -l ${mast} \
                       ${mast}/loader run montec -mix "$SOURCE" "$MASTSOURCE"
                SOURCE=$MASTSOURCE
                fi
                if [[ "$SOURCE" == *.mast ]]; then
                    ${typhonVm}/mt-typhon -l ${mast} -l $PWD \
                        ${mast}/loader run ''${SOURCE%.mast} "$@"
                fi
            fi
            ;;
        dump-mast)
            SOURCE=$2
            if [[ -z $SOURCE ]]; then
                usage 1
            else
                ${typhonVm}/mt-typhon -l ${mast} \
                  ${mast}/loader run tools/dump "$SOURCE"
            fi
            ;;
        format)
            SOURCE=$2
            if [[ -z $SOURCE ]]; then
                usage 1
            else
                ${typhonVm}/mt-typhon -l ${mast} \
                    ${mast}/loader run format "$SOURCE"
            fi
            ;;
        add|rm)
            echo "Unimplemented"
            exit 1
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            usage 1
            ;;
    esac
    '';
    capnpc-script = pkgs.writeScript "capnpc-monte" ''
      #!${shellForMt}
      ${typhonVm}/mt-typhon -l ${mast} \
          ${mast}/loader run tools/capnpc "$@"
    '';

  drvName = "${if withBuild then "monte" else "monte-lite"}-${typhonVm.name}";
in
  stdenv.mkDerivation {
    name = drvName;
    buildInputs = [ typhonVm mast rlwrap ] ++ (if withBuild then [ nix-prefetch-scripts ] else []);
    buildPhase = ''
      '';
    installPhase = ''
      set -e
      mkdir -p $out/bin
      mkdir -p $out/nix-support
      for expr in typhon vm monte-script montePackage mast; do
        cp nix-support/$expr.nix $out/nix-support
      done
      ln -s ${mt-bake-py} $out/nix-support/mt-bake.py
      substituteAll ${mt-script} $out/bin/monte
      substituteAll ${capnpc-script} $out/bin/capnpc-monte
      chmod +x $out/bin/monte $out/bin/capnpc-monte
      '';
    src = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      lib.hasPrefix (loc "/nix-support") (toString path)) ./..;
  }
