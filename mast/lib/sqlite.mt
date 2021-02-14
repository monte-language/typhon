import "lib/codec/utf8" =~ [=> UTF8]
import "lib/streams" =~ [=> collectBytes]
exports (connectSQLite)

def parseCSV(bs :Bytes) :List[List[Str]] as DeepFrozen:
    def decoded := UTF8.decode(bs, null)
    def lines := decoded.split("\n")
    # Discard final line, as it is always empty.
    return [for line in (lines.slice(0, lines.size() - 1)) {
        # XXX write a real CSV parser? Require SQLite to support JSON?
        line.split(",")
    }]

def flags :List[Bytes] := [b`-bail`, b`-csv`, b`-batch`]

def connectSQLite(sqlite3, path :Str) as DeepFrozen:
    "
    Use `sqlite3` as a subprocess to open `path`, a database located on the
    local filesystem.

    For example, `which(\"sqlite3\")` will get an appropriate tool.
    "

    def encodedPath :Bytes := UTF8.encode(path, null)

    def doQuery(sql :Str, => readOnly :Bool):
        def encodedSQL :Bytes := UTF8.encode(sql, null)
        def args :List[Bytes] := (flags + readOnly.pick([b`-readonly`], []) +
                                  [encodedPath, encodedSQL])
        def p := sqlite3<-(args, [].asMap(), "stdout" => true)
        return when (def bs := collectBytes(p<-stdout())) ->
            parseCSV(bs)

    return object SQLiteConnection:
        to version():
            def p := sqlite3<-([b`-version`], [].asMap(), "stdout" => true)
            return collectBytes(p<-stdout())

        to query(sql :Str):
            "Send some raw `sql` to the database in read-only mode."

            return doQuery(sql, "readOnly" => true)

        to update(sql :Str):
            "Send some raw `sql` to the database in read-write mode."

            return doQuery(sql, "readOnly" => false)
