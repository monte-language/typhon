FETCHERS = {
    'git': '/home/washort/.nix-profile/bin/nix-prefetch-git'
}
import os
import json
import subprocess

data = json.load(open("mt.json"))

# Generate snippets for fetching all dependencies specified in the package.
deps = data.get("dependencies", {}).items()
depUrlsSeen = set(d[1]['url'] for d in deps)
srcDepExprs = []
depExprs = []
env = os.environ.copy()
env["PRINT_PATH"] = "1"
for depname, dep in deps:
    result = subprocess.check_output(
        [FETCHERS[dep.get("type", "git")], dep["url"]],
        env=env)
    lines = result.split("\n")
    commitStr = lines[0].strip().split()[-1]
    hashStr = lines[2].strip()
    depPath = lines[3].strip()
    srcDepExprs.append(
        '  %s_src = fetchgit { url = "%s"; rev = "%s"; sha256 = "%s"; };\n' % (
            depname, dep["url"], commitStr, hashStr))
    subdata = json.load(open(os.path.join(depPath, "mt.json")))
    depExprs.append("""
  %s = buildMtPkg {
    src = %s_src;
    dependencies = [ %s ];
    name = "%s";
    pathNames = [ %s ];
    };
    """ % (subdata["name"],
           subdata["name"],
           " ".join(subdata.get("dependencies", {}).keys()),
           subdata["name"],
           " ".join('"%s"' % p for p in subdata["paths"])))
    # Collect all dependencies of this library and append new ones to the list.
    for (k, v) in subdata.get("dependencies", {}).iteritems():
        if v not in depUrlsSeen:
            depUrlsSeen.add(v['url'])
            deps.append(k, v)

entrypoint = "null"

if "entrypoint" in data:
    entrypoint = '"%s"' % data['entrypoint']

pathNames = " ".join('"%s"' % p for p in data["paths"])
paths = " ".join("./%s" % p for p in data["paths"])
nixExpr = """
{stdenv, lib, fetchgit, typhonVm, mast}:
let
  %s
  %s
  buildMtPkg = {src, name, dependencies, entrypoint ? null, pathNames}:
    stdenv.mkDerivation {
      name = name;
      buildInputs = [ typhonVm mast ] ++ dependencies;
      buildPhase = "
      for srcP in ${lib.concatStringsSep " " pathNames}; do
        for srcF in `find ./$srcP -name \\\\*.mt`; do
          destF=\\${srcF%%.mt}.mast
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
        ls -al $p
        mkdir -p $out/$p
        cp -r $p/ $out/$p
      done
      " + (if (entrypoint != null) then
        let dependencySearchPaths = lib.concatStringsSep " " (map (x: "-l " + x) dependencies);
        in ''
        mkdir -p $out/bin
      echo "${typhonVm}/mt-typhon ${dependencySearchPaths} -l ${mast}/mast -l $out ${mast}/loader run ${entrypoint} \\"\\$@\\"" > $out/bin/${entrypoint}
      chmod +x $out/bin/${entrypoint}
      '' else "");
      doCheck = false;
      src = src;
  };
in
buildMtPkg {
  dependencies = [ %s ];
  name = "%s";
  entrypoint = %s;
  pathNames = [ %s ];
  src = builtins.filterSource (path: type: lib.any (p: lib.hasPrefix (toString p) path) [ %s ]) ./.;
}
""" % (''.join(srcDepExprs), ''.join(depExprs),
       ' '.join(d[0] for d in deps), data["name"],
       entrypoint, pathNames, paths)

open("default.nix", "w").write(nixExpr)
