class Span(object):
    """
    A possibly-one-to-one region within a two-dimensional layout.
    """

    _immutable_ = True

    def __init__(self, source, isOneToOne, startLine, startCol, endLine,
                 endCol):
        self.source = source
        self.isOneToOne = isOneToOne
        self.startLine = startLine
        self.startCol = startCol
        self.endLine = endLine
        self.endCol = endCol

    def toString(self):
        if self.isOneToOne:
            fragType = u'span'
        else:
            fragType = u'blob'
        return u'<%s#:%s::%s:%s::%s:%s>' % (
            self.source, fragType,
            str(self.startLine).decode('utf-8'),
            str(self.startCol).decode('utf-8'),
            str(self.endLine).decode('utf-8'),
            str(self.endCol).decode('utf-8'))
