
require! \ops

merge = (...dicts) ->
  o = {}
  for d in dicts then for k, v of d then o[k] = v
  o

appends = (...arrs) -> [].concat ...arrs

intercalate = (e, arr) ->
  r = []
  for i from 0 til arr.length - 1 then r.push arr[i], e
  r.push arr[arr.length - 1]
  r


free-set = (x, bound = {}) ->
  switch typeof! x
    case \String =>
      if x of bound then {} else { +"#x" }
    case \Array =>
      switch x.0
        case \quote   => {}
        case \lambda  =>
          free-set x[2 to ], (bound `merge` {[v, true] for v in x.1})
        case \if      =>
          (free-set x.1, bound) `merge` (free-set x.2, bound) `merge` (free-set x.3, bound)
        case \set!    =>
          free-set x[1 to ], bound
        case \call/cc =>
          free-set x.1, bound
        case \call/native =>
          free-set x[1 to ], bound
        case _ =>
          x |> foldl ((a, x) -> (free-set x, bound) `merge` a), {}
    case _ => {}

mutable-set = (x, vars = {}) ->
  switch typeof! x
    case \Array  =>
      switch x.0
        case \quote   => {}
        case \lambda  =>
          {[v, true] for v, _ of mutable-set x[2 to ], vars when v not in x.1}
        case \if      =>
          (mutable-set x.1, vars) `merge` (mutable-set x.2, vars) `merge` (mutable-set x.3, vars)
        case \set!    =>
          (mutable-set x.2, vars) `merge` (if x.1 of vars then { +"#{x.1}" } else {})
        case \call/cc =>
          mutable-set x.1, vars
        case \call/native =>
          mutable-set x[1 to ], vars
        case _ =>
          x |> foldl ((a, x) -> (mutable-set x, vars) `merge` a), {}
    case _ => {}

static-refer = (x, e) ->
  case x in e[]local => ops.refer-local(e.local.index-of x)
  case x in e[]free  => ops.refer-free (e.free .index-of x)
  case _             => ops.refer-global x

static-assign = (id, e) ->
  case id in e[]local => ops.assign-local(e.local.index-of id)
  case id in e[]free  => ops.assign-free (e.free .index-of id)
  case _              => throw "set!: not a local variable: #id"

env-contains = (x, e) -> x in e[]local or x in e[]free

compile-expr = (x, e, s) ->
  switch typeof! x

    case \String =>
      [ static-refer x, e ] ++ (s[x] and [ ops.indirect ] or [ ])

    case \Array =>
      switch x.0

        case \quote => [ ops.constant x.1 ]

        case \lambda =>

          varset  = {[v, true] for v in x.1}
          freeset = {[v, true] for v of (free-set x[2 to ], varset)
                              when env-contains v, e}
          mutset  = mutable-set x[2 to ], varset
          freevec = [v for v, _ of freeset]

          new-e = local: x.1, free: freevec
          new-s = mutset `merge` {[v, true] for v, _ of freeset when v of s}

          appends do
            ...[ [ (static-refer v, e), ops.argument ] for v in freevec ]
            [ ops.close (length freeset), (length varset), appends do
                [ ops.box n for v, n in x.1 when v of mutset ]
                ...[ compile-expr xpr, new-e, new-s for xpr in x[2 til x.length - 1] ]
                compile-tail x[x.length - 1], new-e, new-s, x.1.length ]

        case \if =>

          conseq = compile-expr x.2, e, s
          alter  = compile-expr x.3, e, s
          appends do
            compile-expr x.1, e, s
            [ ops.test (1 + length conseq) ], conseq, [ ops.skip length alter ], alter

        case \set! =>
          (compile-expr x.2, e, s) ++ [ static-assign x.1, e ]

#          case \call/cc =>
#            call = [ conti, [ argument, compile x.1, e, s,
#                      if next.0 isnt ret then [ apply, 1 ]
#                      else [ shift, 1, next.1, [ apply, 1 ] ] ] ]
#            if next.0 is ret then call else [ frame, next, call ]

        case \native =>
          appends do
            ...(reverse intercalate [ ops.argument ], (map (compile-expr _, e, s), x[1 to ]))
            [ ops.apply-native (x.length - 2) ]

        case _ =>
          argn = x.length - 1

          call = appends do
            ...(reverse intercalate [ ops.argument ], (map (compile-expr _, e, s), x))
            [ ops.apply argn ]
          [ ops.frame length call ] ++ call

    case _ => [ ops.constant x ]


compile-tail = (x, e, s, ret-len) ->
  case typeof! x is \Array =>
    switch

      case x.0 in [\quote \lambda \set! \call/cc \call/native] =>
        (compile-expr x, e, s) ++ [ ops.ret ret-len ]

      case x.0 is \if =>
        conseq = compile-tail x.2, e, s, ret-len
        alter  = compile-tail x.3, e, s, ret-len
        appends do
          compile-expr x.1, e, s
          [ ops.test length conseq ], conseq, alter

      case _ =>
        argn = x.length - 1
        appends do
          ...(reverse intercalate [ ops.argument ], (map (compile-expr _, e, s), x))
          [ (ops.shift argn, ret-len), (ops.apply argn) ]

  case _ => (compile-expr x, e, s) ++ [ ops.ret ret-len ]



compile = (x) -> (compile-expr x, {}, {}) ++ [ ops.halt ]

module.exports = { compile }
