```
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/http/tag" =~ [=> tag]
import "lib/muffin" =~ [=> loadAnySource]
import "lib/streams" =~ [=> collectBytes]
import "lib/which" =~ [=> makePathSearcher, => makeWhich]
exports (main)
```

# Documentation Generator

This tool looks at a directory of Monte source code and generates a directory
of HTML documentation.

## Walking the Filesystem

There's no low-level directory-walking tool. We can build one, though.
We'll want to visit each directory before its contents, so that we can make
new subdirectories in the output directory.

```
def walkAt(fileResource, visitor, => segments :List[Str] := []) as DeepFrozen:
    def path :Str := "/".join(segments)
    def stats := fileResource<-getStatistics()
    return when (stats) ->
        switch (stats.fileType()):
            match =="directory":
                def visit := visitor.directory(path)
                def ls := fileResource<-getListing()
                when (visit, ls) ->
                    promiseAllFulfilled([for l in (ls) {
                        walkAt(fileResource<-child(l), visitor,
                               "segments" => segments.with(l))
                    }])
            match =="regular file":
                visitor.file(path)
```

We will want to create directories if they don't exist. We can do this in the
traditional fashion, by calling [stat](https://linux.die.net/man/2/stat). If
the syscall returns an error, then the directory doesn't exist. We'll still
propagate any error from the actual [mkdir](https://linux.die.net/man/2/mkdir)
call.

```
def ensureDirExists(fileResource) as DeepFrozen:
    return when (fileResource<-getStatistics()) ->
        null
    catch _problem:
        fileResource<-makeDirectory()
```

## Extracting Metadata from Markdown

For literate Monte files, we can guess their title by looking for a top-level
header.

```
def extractMarkdownTitle(file :Bytes) :NullOk[Bytes] as DeepFrozen:
    var inMarkup :Bool := true
    for line in (file.split(b`$\n`)):
        if (line == b````````):
            inMarkup := !inMarkup
        else if (inMarkup && line =~ b`# @title`):
            return title
    return null
```

## Discovering exported APIs

For any supported source file, we want to load it somewhat, so that we can
examine it. This is mostly parsing, but can include code generation or
tree-walking. After it's loaded, then we can examine it to discover the
documentation for its exported names.

Finding object expressions in a module's AST is only a little tedious.

```
def findObjects(body :DeepFrozen, names :List[Str]) as DeepFrozen:
    return switch (body.getNodeName()):
        match =="ObjectExpr":
            def objName := body.getName().getNoun().getName()
            [for name in (names) name => if (name == objName) { body }]
        match =="SeqExpr":
            def rv := [for name in (names) name => null].diverge()
            for expr in (body.getExprs()):
                if (expr.getNodeName() == "ObjectExpr"):
                    def objName := expr.getName().getNoun().getName()
                    if (rv.contains(objName)):
                        rv[objName] := expr
            rv.snapshot()
        match nodeName:
            traceln(`findObjects: Can't handle $nodeName at ${body.getSpan()}`)
            [for name in (names) name => null]
```

Monte docstrings tend to be indented. When this happens, then we'll dedent
them so that Pandoc's Markdown filter doesn't think that they're code
literals, but documentation literals. We're going to be relatively inflexible
on which indentation pattern we accept, but this is motivated by Monte's
inflexible lexer.

```
def cleanDocstring(ds :NullOk[Str]) :Str as DeepFrozen:
    return if (ds == null) {
        "(undocumented)"
    } else if (ds.startsWith("\n")) {
        var indent := 0
        while (ds[indent + 1] == ' ') { indent += 1 }
        "\n".join([for line in (ds.split("\n")) line.slice(indent, line.size())])
    } else { ds }
```

And we can assemble the final API documentation from those discovered objects.

```
def discoverAPI(module :DeepFrozen) as DeepFrozen:
    if (module.getNodeName() != "Module"):
        return "(can't extract from non-modules yet)"

    def exs := [for ex in (module.getExports()) ex.getName()]
    def objs := findObjects(module.getBody(), exs)
    def exportedDocs := [for name => obj in (objs) {
        def docstring := if (obj == null) { "(name not found)" } else {
            cleanDocstring(obj.getDocstring())
        }
        `
## $name

$docstring
`
    }]
    return "\n".join([`# Exported API`] + exportedDocs)
```

## Calling Pandoc

In general, Pandoc wants to be incanted like this:

    pandoc -f markdown -t html -s -o module.html module.mt.md

If we leave off the final argument, then Pandoc will read standard input.

```
def configurePandoc(pandoc, via (UTF8.encode) inputBase :Bytes,
                    via (UTF8.encode) outputBase :Bytes,
                    outputFormat :Bytes) as DeepFrozen:
    return object runPandoc:
        to run(via (UTF8.encode) fromPath :Bytes,
               via (UTF8.encode) toPath :Bytes,
               title :NullOk[Bytes]):
            def t := if (title == null) { b`Monte Documentation` } else { title }
            def args := [
                b`--from`, b`markdown`,
                b`--to`, outputFormat,
                b`--standalone`,
                b`--output`, b`$outputBase/$toPath`,
                b`--metadata`, b`title=$t`,
                b`$inputBase/$fromPath`,
            ]

            def process := pandoc<-(args, [].asMap(), "stderr" => true)
            def stderr := collectBytes(process<-stderr())
            when (stderr) ->
                if (!stderr.isEmpty()):
                    traceln("Pandoc stderr", stderr)
            return process<-wait()

        to fromBytes(bs :Bytes,
                     via (UTF8.encode) toPath :Bytes,
                     title :NullOk[Bytes]):
            def t := if (title == null) { b`Monte Documentation` } else { title }
            # NB: Give no arguments in order to read from stdin.
            def args := [
                b`--from`, b`markdown`,
                b`--to`, outputFormat,
                b`--standalone`,
                b`--output`, b`$outputBase/$toPath`,
                b`--metadata`, b`title=$t`,
            ]

            def process := pandoc<-(args, [].asMap(), "stdin" => true,
                                    "stderr" => true)
            def stdin := process<-stdin()
            when (stdin<-(bs), stdin<-complete()) ->
                null
            catch problem:
                traceln("Problem feeding Pandoc", problem)
            def stderr := collectBytes(process<-stderr())
            when (stderr) ->
                if (!stderr.isEmpty()):
                    traceln("Pandoc stderr", stderr)
            return process<-wait()
```

## Generating an Index

We could use Pandoc to generate the index HTML, but we'll hand-generate it for
now.

```
def prepareIndex(pages :List) :Str as DeepFrozen:
    def links := tag.ul([for [base, target, title] in (pages.sort()) {
        if (title == null) {
            tag.li(tag.a(tag.code(base), "href" => target))
        } else {
            def via (UTF8.decode) t := title
            tag.li(tag.a(tag.code(base), `: $t`, "href" => target))
        }
    }])
    return "<!DOCTYPE html>" + links.asStr()
```

## Entrypoint

The actual output format could be configured to anything which Pandoc
supports, but we're starting with HTML.

```
def outputFormat :Bytes := b`html`
```

Our main entrypoint will take two arguments, the input and output directories.

```
def main(argv, => currentProcess, => makeFileResource, => makeProcess) as DeepFrozen:
    def [inputDir, outputDir] := argv.slice(argv.size() - 2, argv.size())
    def paths := currentProcess.getEnvironment()[b`PATH`]
    def searcher := makePathSearcher(makeFileResource, paths)
    def which := makeWhich(makeProcess, searcher)
    traceln(`Input directory: $inputDir`)
    traceln(`Output directory: $outputDir`)
    traceln(`Output format: $outputFormat`)

    def pandoc := which("pandoc")
    return when (pandoc) ->
        traceln(`Got Pandoc: $pandoc`)
        def doc := configurePandoc(pandoc, inputDir, outputDir, outputFormat)

        def pages := [].diverge()
        object walk:
            to directory(path :Str):
                def dir := makeFileResource(`$outputDir/$path`)
                return ensureDirExists(dir)

            to file(path :Str):
                def file := makeFileResource(`$inputDir/$path`)
                return if (path =~ `@base.mt.md`):
                    def target := `$base.html`

                    when (def bs := file<-getContents()) ->
                        def title := extractMarkdownTitle(bs)
                        pages.push([base, target, title])
                        doc(path, target, title)
                else if (path =~ `@base.mt`):
                    def target := `$base.html`

                    when (def bs := file<-getContents()) ->
                        def via (UTF8.encode) title := base.split("/").last()
                        def [_, module] := loadAnySource(bs, path, null)
                        def via (UTF8.encode) api := discoverAPI(module)
                        pages.push([base, target, title])
                        doc.fromBytes(api, target, title)

        when (walkAt(makeFileResource(inputDir), walk)) ->
            def via (UTF8.encode) index := prepareIndex(pages.snapshot())
            when (makeFileResource(outputDir).child("index.html").setContents(index)) ->
                0
```
