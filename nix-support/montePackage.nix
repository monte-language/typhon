{stdenv, pkgs, lib, fetchgit, bash, typhonVm, mast}: lock:
let
  fetchSrc = (name: srcDesc:
    if srcDesc.type == "git" then
      fetchgit {
        url = srcDesc.url;
        rev = srcDesc.commit;
        sha256 = srcDesc.hash;
      }
    else if srcDesc.type == "local" then
      srcDesc.path
    else
      null);
  buildMtPkg = {src, name, dependencies, entrypoint, pathNames}:
    let
      dependencySearchPaths = lib.concatStringsSep " " (map (x: "-l " + x) dependencies);
      doCheck = entrypoint != null;
      entryPointName = if entrypoint != null then builtins.trace (baseNameOf entrypoint) (baseNameOf entrypoint) else null;
    in
    stdenv.mkDerivation {
      name = name;
      buildInputs = [ typhonVm mast ] ++ dependencies;
      buildPhase = "
      for srcP in ${lib.concatStringsSep " " pathNames}; do
        for srcF in `find ./$srcP -name \\*.mt`; do
          destF=\${srcF%%.mt}.mast
          ${typhonVm}/mt-typhon -l ${mast}/mast ${mast}/loader run montec -mix $srcF $destF
          fail=$?
          if [ $fail -ne 0 ]; then
              exit $fail
          fi
        done
      done
      ";
      doCheck = doCheck;
      checkPhase = if doCheck then ''
        ${typhonVm}/mt-typhon ${dependencySearchPaths} -l ${mast}/mast -l . ${mast}/loader test ${entrypoint}
      '' else null;
      installPhase = "
      mkdir -p $out
      for p in ${lib.concatStringsSep " " pathNames}; do
        cp -r $p $out/$p
      done
      " + (if doCheck then ''
        mkdir -p $out/bin
        tee $out/bin/${entryPointName} <<EOF
        #!${pkgs.stdenv.shell}
        case \$1 in
          --test)
            shift
            OPERATION=test
            ;;
          --bench)
            shift
            OPERATION=bench
            ;;
          --dot)
            shift
            OPERATION=dot
            ;;
          --run)
            shift
            OPERATION=run
            ;;
          *)
            OPERATION=run
            ;;
        esac
        ${typhonVm}/mt-typhon ${dependencySearchPaths} -l ${mast}/mast -l $out ${mast}/loader \$OPERATION ${entrypoint} "\$@"
        EOF
        chmod +x $out/bin/${entryPointName}
        '' else "");
      src = src;
    };
  makePkg = name: pkg:
    buildMtPkg {
      name = name;
      src = let s = sources.${pkg.source}; in
        if name == lock.mainPackage then
          builtins.filterSource (path: type:
            !(lib.hasPrefix ".git" path) &&
            type != "symlink" &&
            lib.any (p:
               lib.hasPrefix (builtins.toString (builtins.toPath (s + ("/" + p)))) path) pkg.paths)
          s
        else
          s;
      dependencies = map (d: packages.${d}) pkg.dependencies;
      entrypoint = pkg.entrypoint;
      pathNames = pkg.paths;
    };
  sources = lib.mapAttrs fetchSrc lock.sources;
  packages = lib.mapAttrs makePkg lock.packages;
in
packages.${lock.mainPackage}
