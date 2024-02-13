@0xe2597668ccd0fb6a;

struct DataExpr {
  struct Integer {
    union {
      int32  @0 :Int32;
      bigint @1 :Text;
    }
  }

  struct NamedArg {
    key @0 :Text;
    value @1 :DataExpr;
  }

  union {
    literal :union {
      int    @0 :Integer;
      double @1 :Float64;
      str    @2 :Text;
      char   @3 :Int32;
      bytes  @4 :Data;
    }

    noun     @5 :Text;
    ibid     @6 :Int32;

    call :group {
      receiver  @7 :DataExpr;
      message   :group {
        verb      @8 :Text;
        args      @9 :List(DataExpr);
        namedArgs @10 :List(NamedArg);
      }
    }

    defExpr :group {
      index  @11 :Int32;
      rValue @12 :DataExpr;
    }

    defRec :group {
      promIndex @13 :Int32;
      rValue    @14 :DataExpr;
    }
  }
}
