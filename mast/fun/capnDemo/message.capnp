@0xb697ff2d05a5bffd;

struct Sum {
  a @0 :Int64;
  b @1 :Int64;
}

struct Result {
  result @0 :Int64;
}

struct Message {
  message :union {
    request @0 :Sum;
    response @1 :Result;
  }
}
