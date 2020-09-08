from unittest import TestCase

from typhon.nanopass import makeIR, withHoles

ir = makeIR(
    "Test",
    ["Noun", "Literal"],
    {
        "Expr": {
            "DefExpr": [("patt", "Patt"), ("rvalue", "Expr")],
            "NounExpr": [("name", "Noun")],
            "LiteralExpr": [("val", "Literal")],
            "SeqExpr": [("exprs", "Expr*")]
            },
        "Patt": {
            "FinalPatt": [("name", "Noun")],
            "VarPatt": [("name", "Noun")],
        }
    })

class IRDestructuringTests(TestCase):
    def test_terminalHole(self):
        qir = withHoles(ir)
        ast1 = ir.NounExpr("blee")
        qast = qir.NounExpr(qir.HOLE("name"))

        self.assertEqual(qast.match(ast1), {"name": "blee"})

    def test_nontermHole(self):
        qir = withHoles(ir)
        p = ir.FinalPatt("foo")
        ast1 = ir.DefExpr(p, ir.NounExpr("blee"))
        qast = qir.DefExpr(qir.HOLE("patt"), qir.NounExpr("blee"))

        self.assertEqual(qast.match(ast1), {"patt": p})

    def test_nonmatchTerminal(self):
        qir = withHoles(ir)
        p = ir.FinalPatt("foo")
        ast1 = ir.DefExpr(p, ir.NounExpr("baz"))
        qast = qir.DefExpr(qir.HOLE("patt"), qir.NounExpr("blee"))
        with self.assertRaises(ValueError) as ve:
            qast.match(ast1)
        self.assertEqual(ve.exception.message, "Expected 'blee', got 'baz'")

    def test_nonmatchNonterm(self):
        qir = withHoles(ir)
        p = ir.FinalPatt("foo")
        ast1 = ir.DefExpr(p, ir.LiteralExpr(1))
        qast = qir.DefExpr(qir.HOLE("patt"), qir.NounExpr("blee"))
        with self.assertRaises(ValueError) as ve:
            qast.match(ast1)
        self.assertEqual(ve.exception.message, "Expected NounExpr3, got LiteralExpr5")

    def test_nonmatchNontermType(self):
        qir = withHoles(ir)
        p = ir.FinalPatt("foo")
        ast1 = ir.DefExpr(p, ir.LiteralExpr(1))
        qast = qir.DefExpr(qir.HOLE("patt", qir.VarPatt), ir.LiteralExpr(1))
        with self.assertRaises(ValueError) as ve:
            qast.match(ast1)
        self.assertEqual(ve.exception.message, "Expected VarPatt8, got FinalPatt7")
