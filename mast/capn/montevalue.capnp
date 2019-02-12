@0xe2597668ccd0fb6a;

struct MonteValue {
  null @0 :Void;
  bool @1 :Bool;
  int @2 :Int32;
  bigint @3 :Data;
  double @4 :Float64;
  bytes @5 :Data;
  text @6 :Text;
  list @7 :List(MonteValue);
}

struct NamedArg {
  key @0 :Text;
  value @1 :MonteValue;
}

struct MonteMessage {
  verb @0 :Text;
  args @1 :List(MonteValue);
  namedArgs @2 :List(NamedArg);
}
