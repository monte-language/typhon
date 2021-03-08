```
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/http/tag" =~ [=> tag]
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

## Calling Pandoc

In general, Pandoc wants to be incanted like this:

    pandoc -f markdown -t html -s -o module.html module.mt.md

```
def configurePandoc(pandoc, via (UTF8.encode) inputBase :Bytes,
                    via (UTF8.encode) outputBase :Bytes,
                    outputFormat :Bytes) as DeepFrozen:
    return def runPandoc(via (UTF8.encode) fromPath :Bytes,
                         via (UTF8.encode) toPath :Bytes):
        def args := [
            b`--from`, b`markdown`,
            b`--to`, outputFormat,
            b`--standalone`,
            b`--output`, b`$outputBase/$toPath`,
            b`--metadata`, b`title=Monte Docs`,
            b`$inputBase/$fromPath`,
        ]
        def process := pandoc<-(args, [].asMap(), "stderr" => true)
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
    def links := tag.ul([for [base, target] in (pages) {
        tag.li(tag.a(base, "href" => target))
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
                return if (path =~ `@base.mt.md`):
                    def target := `$base.html`
                    pages.push([base, target])
                    doc(path, target)

        when (walkAt(makeFileResource(inputDir), walk)) ->
            def via (UTF8.encode) index := prepareIndex(pages.snapshot())
            when (makeFileResource(outputDir).child("index.html").setContents(index)) ->
                0
```
