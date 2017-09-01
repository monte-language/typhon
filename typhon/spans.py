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
