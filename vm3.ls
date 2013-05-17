
require! \./prims

representation = (x) ->
  switch typeof! x
    case \String    => "\"#{x}\""
    case \Number    => "#{x}"
    case \Boolean   => "#{x}"
    case \Null      => "null"
    case \Undefined => "undefined"

class ctx

  ->
    [ @fragments, @props, @uniq ] = [ [], {}, 0 ]

  emit : (...frgs) ->
    @fragments.push ...[ "  #{f}" for f in frgs ] ; @

  statement: (...frgs) ->
    @fragments.push ...[ "  #{f};\n" for f in frgs] ; @

  note : (...notes) ->
    @fragments.push "\n", ...[ "  // #{n}\n" for n in notes ] ; @

  constant : (v) ->
    p-name = "__constant__#{@uniq++}"
    @props[p-name] = v
    p-name

  finalize: ->

    code = """
( function (regs, genv) {
  var stack = regs.stack ,
  env   = regs.env   ,
  acc   = regs.acc   ,
  frame = regs.frame ,
  fun   = regs.fun   ;
#{ @fragments.join '' }
})"""

    vop =
      invoke      : sanitized-eval code
      __closure__ : prims.Closure
      __cell__    : prims.Cell

    for pn, pv of @props then vop[pn] = pv

    console
      ..log 'link >>>\n'
      ..log '', vop.invoke
      ..log '\n<<<'
    vop

  with: (...notes, f) ->
    notes |> each ~> @note it
    f.call @

sanitized-eval = (str) -> eval str

link = (bc, genv) -> link-with-k bc, void, genv

link-with-k = (bc, appendix) ->
  case empty bc => appendix
  case _        =>
    c = new ctx
    weave c, bc, appendix
    c.finalize!

weave = (ctx, bc, appendix) ->
  case (empty bc) and (not appendix) =>
  case (empty bc)                    => goto ctx, appendix
  case not ops.has-own-property bc.0.op =>
    console.log "ctx:", ctx, "bc:", bc
    throw new Error "weave: unknown instruction: #{bc.0.op}"
  case _        => ops[bc.0.op] ctx, bc.0, bc[1 to ], appendix

goto = (ctx, appendix) ->
  ctx.with \goto ->
    p-name = @constant appendix
    @statement do
      "regs.fun = this.#{p-name}"
      "regs.acc = acc"

ops =

  \halt : (ctx) ->
    ctx.with \halt ->
      @statement do
        "regs.acc = acc"
        "throw 'halt'"

  \refer-local : (ctx, { index }, rest, a) ->
    ctx.with \refer-local ->
      @statement "acc = stack[frame - #{index}]"
    weave ctx, rest, a

  \refer-free  : (ctx, { index }, rest, a) ->
    ctx.with \refer-free ->
      @statement "acc = env[ #{index} ]"
    weave ctx, rest, a

  \refer-global : (ctx, { name }, rest, a) ->
    ctx.with \refer-global ->
      @statement do
        "if ( ! (genv.hasOwnProperty ( '#{name}' )) ) {
          throw 'undefined #{name}';
        }"
        "acc = genv['#{name}']"
    weave ctx, rest, a

  \indirect : (ctx, {}, rest, a) ->
    ctx.with \indirect ->
      @statement "acc = acc.value"
    weave ctx, rest, a

  \box : (ctx, { index }, rest, a) ->
    ctx.with \box ->
      @statement do
        "var $i = stack.length - #{index + 1}"
        "stack[$i] = new this.__cell__(stack[$i])"
    weave ctx, rest, a

  \constant : (ctx, { value }, rest, a) ->
    ctx.with \constant ->
      if rep = representation value
        @statement "acc = #{rep}"
      else
        p-name = @constant value
        @statement "acc = this.#{p-name}"
    weave ctx, rest, a

  \assign-local : (ctx, { index }, rest, a) ->
    ctx.with \assign-local ->
      @statement do
        "stack[frame - #{index}].value = acc"
        "acc = undefined"
    weave ctx, rest, a

  \assign-free : (ctx, { index }, rest, a) ->
    ctx.with \assign-free ->
      @statement do
        "env[ #{index} ].value = acc"
        "acc = undefined"
    weave ctx, rest, a

  \argument : (ctx, {}, rest, a) ->
    ctx.with \argument ->
      @statement "stack.push(acc)"
    weave ctx, rest, a

  \frame : (ctx, { return-to, proceed }, rest, a) ->
    ctx.with \frame ->
      p-name = @constant link-with-k return-to, a
      @statement "stack.push(env, frame, this.#{p-name})"
    weave ctx, proceed

  \shift : (ctx, { keep, discard }, rest, a) ->
    ctx.with \shift ->
      if discard > 0
        @statement "stack.splice(stack.length - #{keep + discard}, #{discard})"
    weave ctx, rest, a

  \ret : (ctx, { discard }) ->
    ctx.with \ret ->
      if discard > 0
        @statement "stack.splice(stack.length - #{discard})"
      @statement do
        "regs.acc   = acc"
        "regs.fun   = stack.pop()"
        "regs.frame = stack.pop()"
        "regs.env   = stack.pop()"
        "return"

  \test : (ctx, { positive, negative }, rest, a) ->
    join-point = link-with-k rest, a
    ctx.with \test ->
      @emit "if (acc !== false) {"
      weave ctx, positive, join-point
      @emit " } else {"
      weave ctx, negative, join-point
      @emit "}"

  \close : (ctx, { free, arity, body }, rest, a) ->
    ctx.with \close ->
      p-name = @constant link-with-k body
      @statement "var $newenv = []"
      if free > 0
        @statement do
          "for ( var $i = 0; $i < #{free}; $i++ ) { $newenv.push (stack.pop ()); }"
      @statement do
        "acc = new this.__closure__ ( $newenv, #{arity}, this.#{p-name} )"
    weave ctx, rest, a

  \apply : (ctx, { args }) ->
    ctx.with \apply ->
      @statement do
        "if (! (acc instanceof this.__closure__) ) { throw 'not fun'; }"
        "if (! (acc.arity === #{args}) ) { throw 'arity mismatch'; }"
        "regs.fun   = acc.body"
        "regs.env   = acc.env"
        "regs.frame = stack.length - 1"
        "return"

  \apply-native : (ctx, { args }, rest, a) ->
    ctx.with \apply-native ->
      @statement do
        "if (! (acc instanceof Function) ) { throw 'not (native) fun' }"
        "var $args = []"
        "for ( var $i = 0; $i < #{args}; $i++ ) { $args.push(stack.pop ()); }"
        "acc = acc.apply(null, $args)"
    weave ctx, rest, a


dump = (x) ->
  "console.log ('[DUMP] #{x}') ;
   console.log ('   acc :', acc) ;
   console.log ('   env :', env) ;
   console.log ('   frm :', frame ) ;
   console.log ('   stk :', stack) ;"

run-linked = (op, genv) ->

  regs =
    acc   : void
    fun   : op
    frame : 0
    env   : \noenv
    stack : []

  try
    loop
#        console
#          ..log "invoke -->"
#          ..log "    ", regs.fun
#          ..log "    ", regs.fun?.invoke
      regs.fun.invoke regs, genv

  catch e
    unless e is \halt
      console
        ..log ":: unhandled exn ::"
        ..log "  ", e
        ..log regs
      throw e

  regs.acc

run = (bc, genv = new ->) ->
  run-linked (link bc), genv

module.exports = { link, run-linked, run }

require! \compiler

test-me = (prog) ->
  require! \util
  bc = compiler.compile prog
  console.log util.inspect bc, {+colors, depth: null}
  console.log run bc,
    \+ : (a, b) -> a + b
    \cons : (a, b) -> new prims.Cons a, b
    \car  : -> it.car
    \cdr  : -> it.cdr

#  test-me do
#      [[\lambda [] [\if false [\native \+ 1 2] [\native \+ 3 8]]]]
#  #      [[\lambda [\x \y]
#  #        [\set! \x [[\lambda [] [\native \+ \x \y]]]]
#  #        \x]
#  #       1 999]
