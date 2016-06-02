from typhon.nano.mast import MastIR

CheckpointIR = MastIR.extend([],
        {"Expr": {"CheckpointExpr": [("count", None)]}})


class AddCheckpoints(MastIR.makePassTo(CheckpointIR)):

    def visitCallExpr(self, obj, verb, args, namedArgs):
        obj = self.visitExpr(obj)
        args = [self.visitExpr(arg) for arg in args]
        namedArgs = [self.visitNamedArg(namedArg) for namedArg in namedArgs]
        return CheckpointIR.SeqExpr([
            CheckpointIR.CheckpointExpr(1),
            CheckpointIR.CallExpr(obj, verb, args, namedArgs),
        ])


class CollectCheckpoints(CheckpointIR.selfPass()):

    def visitSeqExpr(self, exprs):
        # Build a new SeqExpr, collecting subordinate SeqExprs and
        # checkpoints.
        count = 0
        l = []
        stack = [exprs]
        while stack:
            nextExprs = stack.pop()
            for i, expr in enumerate(nextExprs):
                expr = self.visitExpr(expr)
                if isinstance(expr, CheckpointIR.SeqExpr):
                    # Slice and push.
                    stack.append(nextExprs[i + 1:])
                    stack.append(expr.exprs)
                elif isinstance(expr, CheckpointIR.CheckpointExpr):
                    count += expr.count
                else:
                    l.append(expr)
        if count != 0:
            l.insert(0, CheckpointIR.CheckpointExpr(count))
        return CheckpointIR.SeqExpr(l)
