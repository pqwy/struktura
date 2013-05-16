
require! \./ops
{ init, merge, intercalate, compose-r, compose-l } =
  require \./crap


free-set = (x, bound = {}) ->
  switch typeof! x
    case \String =>
      if x of bound then {} else { +"#x" }
    case \Array =>
      switch x.0
        case \quote   => {}
        case \lambda  =>
          free-set x[2 to ], bound `merge` {[v, true] for v in x.1}
        case \if      =>
          merge do
            free-set x.1, bound
            free-set x.2, bound
            free-set x.3, bound
        case \set!    =>
          free-set x[1 to ], bound
        case \call/cc =>
          free-set x.1, bound
        case \native =>
          free-set x[1 to ], bound
        case _ =>
          x |> foldl ((a, x) -> a `merge` free-set x, bound), {}
    case _ => {}

mutable-set = (x, vars = {}) ->
  switch typeof! x
    case \Array  =>
      switch x.0
        case \quote   => {}
        case \lambda  =>
          {[v, true] for v, _ of mutable-set x[2 to ], vars when v not in x.1}
        case \if      =>
          merge do
            mutable-set x.1, vars
            mutable-set x.2, vars
            mutable-set x.3, vars
        case \set!    =>
          merge do
            mutable-set x.2, vars
            if x.1 of vars then { +"#{x.1}" } else {}
        case \call/cc =>
          mutable-set x.1, vars
        case \native =>
          mutable-set x[1 to ], vars
        case _ =>
          x |> foldl ((a, x) -> a `merge` mutable-set x, vars), {}
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

compile-expr = (e, s, x, next) -->

  switch typeof! x

    case \String =>
      [ static-refer x, e ] ++ (s[x] and [ ops.indirect ] or []) ++ next

    case \Array =>
      switch x.0

        case \quote => [ ops.constant x.1 ] ++ next

        case \lambda =>

          exprs = x[2 to ]

          varset  = {[v, true] for v in x.1}
          freeset = {[v, true] for v of (free-set exprs, varset)
                              when env-contains v, e}
          mutset  = mutable-set exprs, varset
          freevec = [v for v, _ of freeset]

          new-e = local: x.1, free: freevec
          new-s = mutset `merge` {[v, true] for v, _ of freeset when v of s}

          concat [
            ...reverse [ [ (static-refer v, e), ops.argument ] for v in freevec ]
            [ ops.close (length freeset), (length varset), concat [
                [ ops.box n for v, n in x.1 when v of mutset ]
                init exprs |> map (compile-expr new-e, new-s) |> compose-r
                  <| compile-tail new-e, new-s, (last exprs), x.1.length
            ] ]
            next
          ]

        case \if =>

          ( compile-expr e, s, x.1,
              [ ops.test ( compile-expr e, s, x.2, [] ),
                         ( compile-expr e, s, x.3, [] ) ] ) ++ next

        case \set! =>
          compile-expr e, s, x.2, ( [ static-assign x.1, e ] ++ next )

#          case \call/cc =>
#            call = [ conti, [ argument, compile x.1, e, s,
#                      if next.0 isnt ret then [ apply, 1 ]
#                      else [ shift, 1, next.1, [ apply, 1 ] ] ] ]
#            if next.0 is ret then call else [ frame, next, call ]

        case \native =>
          intercalate ([ ops.argument ] ++), map (compile-expr e, s), tail x
            |> compose-l <| [ ops.apply-native (x.length - 2) ] ++ next

        case _ =>
          argn = x.length - 1

          [ ops.frame next,
              intercalate ([ ops.argument ] ++), map (compile-expr e, s), x
                |> compose-l <| [ ops.apply argn ] ]

    case _ => [ ops.constant x ] ++ next


compile-tail = (e, s, x, ret-len) -->
  switch
  case typeof! x is \Array =>
    switch

      case x.0 in [\quote \lambda \set! \call/cc \native] =>
        compile-expr e, s, x, [ ops.ret ret-len ]

      case x.0 is \if =>
        compile-expr e, s, x.1,
          [ ops.test ( compile-tail e, s, x.2, ret-len ),
                     ( compile-tail e, s, x.3, ret-len ) ]

      case _ =>
        argn = x.length - 1

        intercalate ([ ops.argument ] ++), map (compile-expr e, s), x
          |> compose-l <| [ (ops.shift argn, ret-len), (ops.apply argn) ]

  case _ => compile-expr e, s, x, [ ops.ret ret-len ]


compile = (x) -> compile-expr {}, {}, x, [ ops.halt ]

module.exports = { compile }

