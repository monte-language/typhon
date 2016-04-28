{stdenv, pkgs, lib, python27, typhonVm, mast, nix, nix-prefetch-scripts,
 rlwrap}:
let
  mt-bake-py = pkgs.writeText "mt-bake.py" (
  "FETCHERS = {'git': '${nix-prefetch-scripts + "/bin/nix-prefetch-git"}'}\n" +
  builtins.readFile ./mt-bake.py.in);
  mt-script = pkgs.writeScript "mt" ''
    #!${pkgs.stdenv.shell}
    set -x
    OPERATION=$1
    usage() {
        cat <<EOF

    Usage: mt <command>
    Command list:
      repl                  Starts interactive prompt in current package.
      lint <filename>       Reads source file, reports syntax errors.
      bake <filename>       Creates a .mast file from a source file.
      eval <filename>       Execute the code in a single source file.
      build                 Builds the current package, symlinks output as 'result'.
      docker-build          Builds the current package, creates a Docker image.
      add <name> <url>      Add a dependency to this package.
      rm <name>             Remove a dependency from this package.
      run <entrypoint>      Invokes an entrypoint in current package.
      test <entrypoint>     Collects and executes tests defined for entrypoint.
      bench <entrypoint>    Collects and executes benchmarks defined for entrypoint.
      dot <entrypoint>      Creates a .dot graph of dependencies.

    EOF
        exit $1
    }
    doBuild() {
        ${python27}/bin/python ${mt-bake-py} &&
        ${nix.out}/bin/nix-build -E "let pkgs = import <nixpkgs> {}; \
          lockSet = builtins.fromJSON (builtins.readFile ./mt-lock.json); \
          in pkgs.callPackage ${./montePackage.nix} { \
              typhonVm = ${typhonVm}; mast = ${mast}; } lockSet"
    }
    doDockerBuild() {
        ${python27}/bin/python ${mt-bake-py} &&
        ${nix.out}/bin/nix-build -E 'let pkgs = import <nixpkgs> {};
          lockSet = builtins.fromJSON (builtins.readFile ./mt-lock.json);
          scriptName = lockSet.entrypoint;
          monteBase = pkgs.callPackage ${./montePackage.nix} {
              typhonVm = ${typhonVm}; mast = ${mast}; };
          in pkgs.dockerTools.buildImage {
              name = scriptName;
              tag = "latest";
              contents = monteBase lockSet;
              config = {
                Cmd = [ ("/bin/" + scriptName) ];
                WorkingDir = "";
              };
            }'
    }

    RLWRAP=${rlwrap}/bin/rlwrap
    case $OPERATION in
        build)
            doBuild
            ;;
        docker-build)
            doDockerBuild
            ;;
        repl)
            $RLWRAP ${typhonVm}/mt-typhon -l ${mast}/mast -l ${mast} ${mast}/loader run repl
            ;;
        lint)
            shift
            ${typhonVm}/mt-typhon -l ${mast}/mast -l ${mast} ${mast}/loader \
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
                ${typhonVm}/mt-typhon -l ${mast}/mast -l ${mast} ${mast}/loader \
                           run montec -mix "$SOURCE" "''${SOURCE%.mt}.mast"
            fi
            ;;
        eval)
            SOURCE=$2
            if [[ -z $SOURCE ]]; then
                usage 1
            else
                if [[ "$SOURCE" == *.mt ]]; then
                   MASTSOURCE=''${SOURCE%.mt}.mast
                   ${typhonVm}/mt-typhon -l ${mast}/mast -l ${mast} \
                       ${mast}/loader run montec -mix "$SOURCE" "$MASTSOURCE"
                SOURCE=$MASTSOURCE
                fi
                if [[ "$SOURCE" == *.mast ]]; then
                    ${typhonVm}/mt-typhon -l ${mast}/mast -l ${mast} -l $PWD \
                        ${mast}/loader run ''${SOURCE%.mast}
                fi
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
in
  stdenv.mkDerivation {
    name = "mt";
    buildInputs = [ typhonVm mast nix-prefetch-scripts rlwrap ];
    buildPhase = ''
      '';
    installPhase = ''
      set -e
      mkdir -p $out/bin
      mkdir -p $out/nix-support
      cp nix-support/typhon.nix $out/nix-support
      cp nix-support/mt.nix $out/nix-support
      cp nix-support/montePackage.nix $out/nix-support
      ln -s ${mt-bake-py} $out/nix-support/mt-bake.py
      ln -s ${mt-script} $out/bin/mt
      '';
    src = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      lib.hasPrefix (loc "/nix-support") (toString path)) ./..;
  }
