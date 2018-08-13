import "lib/codec/utf8" =~ [=> UTF8]
import "lib/enum" =~ [=> makeEnum]
import "lib/gadts" =~ [=> makeGADT]
import "unittest" =~ [=> unittest :Any]
exports (Headers, emptyHeaders, parseHeader,
         IDENTITY, CHUNKED)

# Common HTTP header structure.

# RFC 7230.

# 4. Transfer Encodings
def [TransferEncoding :DeepFrozen,
     IDENTITY :DeepFrozen,
     CHUNKED :DeepFrozen,
     COMPRESS :DeepFrozen,
     DEFLATE :DeepFrozen,
     GZIP :DeepFrozen,
] := makeEnum(["identity", "chunked", "compress", "deflate", "gzip"])

def parseTransferEncoding(bs :Bytes) :List[TransferEncoding] as DeepFrozen:
    return [for coding in (bs.toLowerCase().split(b`,`))
        switch (coding.trim()) {
            match b`identity` { IDENTITY }
            match b`chunked` { CHUNKED }
            match b`compress` { COMPRESS }
            match b`deflate` { DEFLATE }
            match b`gzip` { GZIP }
        }]

def testTransferEncoding(assert):
    assert.equal(parseTransferEncoding(b`identity`), [IDENTITY])
    assert.equal(parseTransferEncoding(b`Chunked`), [CHUNKED])
    assert.equal(parseTransferEncoding(b`gzip, chunked`), [GZIP, CHUNKED])

unittest([
    testTransferEncoding,
])

def Headers :DeepFrozen := makeGADT("Headers", ["headers" => [
    "contentLength" => NullOk[Int],
    "contentType" => NullOk[Pair[Str, Str]],
    "userAgent" => NullOk[Str],
    "transferEncoding" => List[TransferEncoding],
    "spareHeaders" => Map[Bytes, Bytes],
]])

def emptyHeaders() :Headers as DeepFrozen:
    return Headers.headers(
        "contentLength" => null,
        "contentType" => null,
        "userAgent" => null,
        "transferEncoding" => [],
        "spareHeaders" => [].asMap())

def parseHeader(headers :Headers, bs :Bytes) :Headers as DeepFrozen:
    "Parse a bytestring header and add it to a header record."

    def b`@header:@{var value}` := bs
    value trim= ()
    return switch (header.trim().toLowerCase()):
        match b`content-length`:
            def contentLength := _makeInt.fromBytes(value)
            headers.with(=> contentLength)
        match b`content-type`:
            # XXX should support options, right?
            def via (UTF8.decode) `@type/@subtype` := value
            def contentType := [type, subtype]
            headers.with(=> contentType)
        match b`transfer-encoding`:
            def transferEncoding := parseTransferEncoding(value)
            headers.with(=> transferEncoding)
        match b`user-agent`:
            headers.with("userAgent" => UTF8.decode(value, null))
        match h:
            def spareHeaders := headers.spareHeaders()
            headers.with("spareHeaders" => spareHeaders.with(h, value))

def testParseHeaderTransferEncoding(assert):
    def headers := parseHeader(emptyHeaders(), b`Transfer-Encoding: chunked`)
    assert.equal(headers.transferEncoding(), [CHUNKED])

def testParseHeaderUAFx(assert):
    def ua := b`User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/60.0`
    def headers := parseHeader(emptyHeaders(), ua)
    assert.equal(headers.userAgent(), "Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/60.0")

unittest([
    testParseHeaderTransferEncoding,
    testParseHeaderUAFx,
])
