{stdenv, lib, fetchgit, typhonVm, mast}: lockfile:
let
  data = builtins.fromJSON (builtins.readFile lockfile);
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
      installPhase = "
      for p in ${lib.concatStringsSep " " pathNames}; do
        mkdir -p $out/$p
        cp -r $p/ $out/$p
      done
      " + (if (entrypoint != null) then
        let dependencySearchPaths = lib.concatStringsSep " " (map (x: "-l " + x) dependencies);
        in ''
        mkdir -p $out/bin
      echo "${typhonVm}/mt-typhon ${dependencySearchPaths} -l ${mast}/mast -l $out ${mast}/loader run ${entrypoint} \"\$@\"" > $out/bin/${entrypoint}
      chmod +x $out/bin/${entrypoint}
      '' else "");
      doCheck = false;
      src = src;
    };
  makePkg = name: pkg:
    buildMtPkg {
      name = name;
      src = let s = sources.${pkg.source}; in
        if name == data.entrypoint then
          builtins.filterSource (path: type:
            lib.any (p:
               lib.hasPrefix (builtins.toString (builtins.toPath (s + ("/" + p)))) path) pkg.paths)
          s
        else
          s;
      dependencies = map (d: packages.${d}) pkg.dependencies;
      entrypoint = pkg.entrypoint;
      pathNames = pkg.paths;
    };
  sources = lib.mapAttrs fetchSrc data.sources;
  packages = lib.mapAttrs makePkg data.packages;
in
packages.${data.entrypoint}
