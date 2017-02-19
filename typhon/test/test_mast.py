from unittest import TestCase

from typhon.nanopass import CompilerFailed, withHoles
from typhon.nano.mast import MastIR, SanityCheck, SaveScriptIR as ssi
from typhon.nano.slots import NoAssignIR as nai, RemoveAssign
from typhon.nano.scopes import LayoutIR as li, LayOutScopes, ScopeBox, ScopeItem

def assertAstSame(left, right):
    if left == right:
        return
    if isinstance(left, list):
        if not isinstance(right, list):
            raise AssertionError("%r != %r" % (left, right))
        for l, r in zip(left, right):
            assertAstSame(l, r)
        return

    if type(left) != type(right):
        raise AssertionError("%r instance expected, %s found" %
                             (type(left), type(right)))
    if left._immutable_fields_ and right._immutable_fields_:
        leftR, rightR = left.__reduce__()[2], right.__reduce__()[2]
        for k, v in leftR.iteritems():
            assertAstSame(v, rightR[k])


class SanityCheckTests(TestCase):
    def test_viaPattObjects(self):
        oAst = MastIR.ObjectExpr(
            None,
            MastIR.ViaPatt(MastIR.CallExpr(
                MastIR.NounExpr(u"foo"),
                u"run",
                [MastIR.NounExpr(u"x")], []),
                           MastIR.FinalPatt(u"x", None), None),
            [], [], [])

        self.assertRaises(CompilerFailed, SanityCheck().visitExpr, oAst)


class RemoveAssignTests(TestCase):
    def test_rewriteAssign(self):
        ast1 = ssi.SeqExpr([
            ssi.AssignExpr(u"blee", ssi.IntExpr(1)),
            ssi.NounExpr(u"blee")
            ])
        ast2 = nai.SeqExpr([
            nai.HideExpr(nai.SeqExpr([
                nai.DefExpr(nai.TempPatt(u"_tempAssign"), nai.NullExpr(), nai.IntExpr(1)),
                nai.CallExpr(nai.SlotExpr(u"blee"), u"put",
                             [nai.TempNounExpr(u"_tempAssign")], []),
                nai.TempNounExpr(u"_tempAssign")])),
            nai.NounExpr(u"blee")
            ])

        assertAstSame(ast2, RemoveAssign().visitExpr(ast1))


class LayoutScopesTests(TestCase):
    def test_ifExprSeparateBoxes(self):
        """
        The branches of an 'if' expression create their own scope boxes.
        """
        layouter = LayOutScopes([], "test", False)
        qli = withHoles(li)
        top = layouter.top
        left = ScopeBox(top)
        ast1 = nai.IfExpr(
            nai.DefExpr(nai.FinalPatt(u"a", nai.NullExpr()), nai.NullExpr(),
                        nai.IntExpr(1)),
            nai.SeqExpr([nai.DefExpr(nai.FinalPatt(u"b", nai.NullExpr()),
                                     nai.NullExpr(), nai.IntExpr(2)),
                         nai.CallExpr(nai.NounExpr(u"a"), u"add",
                                      [nai.NounExpr("b")], [])]),
            nai.SeqExpr([nai.DefExpr(nai.FinalPatt(u"b", nai.NullExpr()),
                                     nai.NullExpr(), nai.IntExpr(3)),
                         nai.CallExpr(nai.NounExpr(u"a"), u"add",
                                      [nai.NounExpr("b")], [])]))
        qast2 = qli.IfExpr(
            qli.DefExpr(
                qli.FinalPatt(u"a", qli.NullExpr(), qli.HOLE("APattern")),
                qli.NullExpr(), qli.IntExpr(1)),
            qli.SeqExpr([
                qli.DefExpr(
                    qli.FinalPatt(u"b", qli.NullExpr(),
                                  qli.HOLE("leftBPattern")),
                    qli.NullExpr(), qli.IntExpr(2)),
                qli.CallExpr(qli.NounExpr(u"a", qli.HOLE("leftANoun")),
                             "add", [qli.NounExpr("b", qli.HOLE("leftBNoun"))],
                             [])
            ]),
            qli.SeqExpr([qli.DefExpr(qli.FinalPatt(u"b", qli.NullExpr(),
                                                   qli.HOLE("rightBPattern")),
                                     qli.NullExpr(), qli.IntExpr(3)),
                         qli.CallExpr(
                             qli.NounExpr(u"a", qli.HOLE("rightANoun")),
                             "add", [qli.NounExpr("b",
                                                  qli.HOLE("rightBNoun"))],
                             [])
            ]))
        scopes = qast2.match(layouter.visitExpr(ast1))
        self.assertIsInstance(scopes["APattern"], ScopeBox)
        self.assertIsInstance(scopes["leftBPattern"], ScopeItem)
        self.assertIsInstance(scopes["leftANoun"], ScopeItem)

        self.assertIs(scopes["APattern"].next, top)
        self.assertIs(scopes["leftBPattern"].next, scopes["APattern"])
        self.assertIs(scopes["leftANoun"].next, scopes["leftBPattern"])

        self.assertIsInstance(scopes["rightBPattern"], ScopeBox)
        self.assertIsInstance(scopes["rightANoun"], ScopeItem)

        self.assertIs(scopes["rightBPattern"].next, top)
        self.assertIs(scopes["rightANoun"].next, scopes["rightBPattern"])
