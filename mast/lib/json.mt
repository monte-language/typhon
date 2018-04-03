import "unittest" =~ [=> unittest :Any]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/pen" =~ [=> pk, => makeSlicer]
import "lib/streams" =~ [=> alterSink, => alterSource, => collectStr]
exports (JSON, main)

# The JSON mini-language for data serialization.
# This module contains the following kit:
# * JSON: A codec decoding JSON text to plain Monte values
# * main: A basic tool for testing validity of and pretty-printing JSON text


def specialEncodeChars :Map[Char, Str] := [
    '"' => "\\\"",
    '\\' => "\\\\",
    '/' => "\\/",
    '\b' => "\\b",
    '\f' => "\\f",
    '\n' => "\\n",
    '\r' => "\\r",
    '\t' => "\\t",
]


def parse(s, ej) as DeepFrozen:
    def ws := pk.satisfies(" \n".asSet().contains).zeroOrMore()
    def e := (pk.equals('e') / pk.equals('E')) + (
        pk.equals('+') / pk.equals('-')).optional()
    def zero := '0'.asInteger()
    def digit := pk.satisfies('0'..'9') % fn c { c.asInteger() - zero }
    def digits := digit.oneOrMore() % fn ds {
        var i :Int := 0
        for d in (ds) { i := i * 10 + d }
        i
    }
    def exp := e >> digits
    def frac := pk.equals('.') >> digits
    def int := (pk.equals('-') >> digits) % fn i { -i } / digits
    def number := (int + frac.optional() + exp.optional()) % fn [[i, f], e] {
        var rv := i
        if (f != null) {
            var divisor := 1
            while (divisor < f) { divisor *= 10 }
            rv += f / divisor
        }
        if (e != null) { rv *= 10 ** e }
        rv
    }
    def plainChar(c) :Bool as DeepFrozen:
        return c != '"' && c != '\\'
    def hex := digit / pk.mapping([
        'a' => 10, 'b' => 11, 'c' => 12,
        'd' => 13, 'e' => 14, 'f' => 15,
        'A' => 10, 'B' => 11, 'C' => 12,
        'D' => 13, 'E' => 14, 'F' => 15,
    ])
    def unicodeEscape := hex * 4 % fn [x, y, z, w] {
        '\x00' + (x * (16 ** 3) + y * (16 ** 2) + z * 16 + w)
    }
    def char := pk.satisfies(plainChar) / (pk.equals('\\') >> (pk.mapping([
        '"' => '"',
        '\\' => '\\',
        '/' => '/',
        'b' => '\b',
        'f' => '\f',
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
    ]) / (pk.equals('u') >> unicodeEscape)))
    def quote := pk.equals('"')
    def comma := ws >> pk.equals(',')
    def string := (char.zeroOrMore() % _makeStr.fromChars).bracket(quote, quote)
    def constant := (pk.string("true") >> pk.pure(true)) / (
        pk.string("false") >> pk.pure(false)) / (pk.string("null") >> pk.pure(null))
    def array
    def obj
    def value := ws >> (string / number / obj / array / constant)
    def elements := value.joinedBy(comma)
    bind array := (elements / pk.pure([])).bracket(pk.equals('['), ws >> pk.equals(']'))
    def pair := ((ws >> string << ws << pk.equals(':')) + value)
    def members := pair.joinedBy(comma) % _makeMap.fromPairs
    bind obj := (members / pk.pure([].asMap())).bracket(pk.equals('{'), ws >> pk.equals('}'))

    def slicer := makeSlicer.fromString(s)
    return value(slicer, ej)[0]


object JSON as DeepFrozen:
    "The JSON data format."

    to decode(specimen, ej):
        def s :Str exit ej := specimen
        return parse(s, ej)

    to encode(specimen, ej) :Str:
        return switch (specimen):
            match m :Map:
                def pieces := [].diverge()
                for k => v in (m):
                    def s :Str exit ej := k
                    def es := JSON.encodeStr(s)
                    def ev := JSON.encode(v, ej)
                    pieces.push(`$es:$ev`)
                `{${",".join(pieces)}}`
            match l :List:
                def pieces := [for i in (l) JSON.encode(i, ej)]
                `[${",".join(pieces)}]`
            match i :Int:
                M.toString(i)
            match d :Double:
                M.toString(d)
            match s :Str:
                JSON.encodeStr(s)
            match c :Char:
                JSON.encodeStr(c.asString())
            match ==true:
                "true"
            match ==false:
                "false"
            match ==null:
                "null"
            match _:
                throw.eject(ej, `$specimen isn't representable in JSON`)

    to encodeStr(s :Str) :Str:
        def pieces := [for c in (s)
                       specialEncodeChars.fetch(c, fn {c.asString()})]
        return `"${"".join(pieces)}"`


def decoderSamples := [
    "{\"first\":42,\"second\":[5,7]}" => ["first" => 42, "second" => [5, 7]],
    `["\u00e9"]` => ["é"],
    "{\"face\\/off\":1997}" => ["face/off" => 1997],
    `{"first":{"second":{"third":42}}}` => ["first" => ["second" => ["third" => 42]]],
    # Yeah, these two tests really are supposed to be this precise. Any
    # imprecisions here should be due to implementation error, AFAICT.
    `{"pi":3.14}` => ["pi" => 3.14],
    `{"nine":3e2}` => ["nine" => 300],
    `{"digits":0.7937000378463977}` => ["digits" => 0.7937000378463977],
    `{"x": null}` => ["x" => null],
]

def testJSONDecode(assert):
    for specimen => value in (decoderSamples):
        escape ej:
            def result := JSON.decode(specimen, ej)
            assert.equal(result, value)
        catch problem:
            traceln("Parser failure:", specimen, problem)
            assert.fail(problem)

def testJSONDecodeInvalid(assert):
    def specimens := [
        "",
        "{",
        "}",
        "asdf",
        "{asdf}",
    ]
    for s in (specimens):
        assert.ejects(fn ej { JSON.decode(s, ej) })

def encoderSamples := [
    ["first" => 42, "second" => [5, 7]] => "{\"first\":42,\"second\":[5,7]}",
]

def testJSONEncode(assert):
    for specimen => value in (encoderSamples):
        assert.equal(JSON.encode(specimen, null), value)

unittest([
    testJSONDecode,
    testJSONDecodeInvalid,
    testJSONEncode,
])

def main(_, => stdio) as DeepFrozen:
    # Buffer it all; we don't really support incremental parsing yet.
    def stdin := alterSource.decodeWith(UTF8, stdio.stdin())
    def stdout := alterSink.encodeWith(UTF8, stdio.stdout())
    def input := collectStr(stdin)
    return when (input) ->
        stdout<-(`1 $input$\n`)
        escape ej:
            def json := JSON.decode(input, ej)
            stdout<-(`2 $json$\n`)
            stdout<-(M.toQuote(json))
            stdout<-("\n")
            when (stdout<-complete()) -> { 0 }
        catch problem:
            when (stdout<-(`Couldn't decode JSON: $problem$\n`)) -> { 1 }
    catch problem:
        when (stdout<-(`Uh oh, $problem$\n`)) -> { 1 }
