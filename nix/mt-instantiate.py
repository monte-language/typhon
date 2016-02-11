import json


data = json.load(open('mt-lock.json'))


def genSource(name, s):
    if s['type'] == 'git':
        return (
            '  %s_src = fetchgit { url = "%s"; rev = "%s";'
            ' sha256 = "%s"; };\n' % (
                name, s["url"], s['commit'], s['hash']))
    elif s['type'] == 'local':
        return ' ' + name + '_src = ' + s['path'] + ';'


def genPackage(name, p, source=None):
    pathNames = " ".join('"%s"' % path for path in p["paths"])
    entrypoint = "null"
    if "entrypoint" in data:
        entrypoint = '"%s"' % p['entrypoint']
    return """
  %s = buildMtPkg {
    src = %s_src;
    dependencies = [ %s ];
    name = "%s";
    entrypoint = %s;
    pathNames = [ %s ];
    };
    """ % (name, source or p['source'],
           " ".join(p['dependencies']), name,
           entrypoint, pathNames)


toplevelName = data['entrypoint']
toplevel = data['packages'].pop(toplevelName)
toplevelPkg = genPackage(
    toplevelName, toplevel,
    source='builtins.filterSource (path: type: lib.any '
    '(p: lib.hasPrefix (toString p) path) [ %s ]) %s' % (
        ' '.join('./' + p for p in toplevel['paths']), toplevel['source']))

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
%s
""" % (
    '\n'.join(genSource(n, s) for n, s in data['sources'].items()),
    '\n'.join([genPackage(n, p) for n, p in data['packages'].items()] +
            [toplevelPkg]),
    toplevelName
)
open("default.nix", 'w').write(nixExpr)
