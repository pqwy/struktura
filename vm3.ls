
require! \./prims

representation = (x) ->
  switch typeof! x
    case \String    => "\"#{x}\""
    case \Number    => "#{x}"
    case \Boolean   => "#{x}"
    case \Null      => "null"
    case \Undefined => "undefined"

class ctx

  -> [ @fragments, @props, @uniq ] = [ [], {}, 0 ]

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
      ..log 'compile >>>\n'
      ..log '', vop.invoke
      ..log '\n<<<'
    vop

  with: (...notes, f) ->
    notes |> each ~> @note it
    f.call @

sanitized-eval = (str) ->
  "use strict"
  eval str

link = (bc) -> weave (new ctx), bc

weave = (ctx, bc) ->
  case empty bc =>
    throw new Error "weave: reached end-of-stream"
  case not ops.has-own-property bc.0.op =>
    console.log "ctx:", ctx, "bc:", bc
    throw new Error "weave: unknown instruction: #{bc.0.op}"
  case _        => ops[bc.0.op] ctx, bc.0, bc[1 to ]

ops =

  \halt : (ctx) ->
    ctx.with \halt ->
      @statement do
        "regs.acc = acc"
        "throw 'halt'"
      @finalize!

  \refer-local : (ctx, { index }, rest) ->
    ctx.with \refer-local ->
      @statement "acc = stack[frame - #{index}]"
    weave ctx, rest

  \refer-free  : (ctx, { index }, rest) ->
    ctx.with \refer-free ->
      @statement "acc = env[ #{index} ]"
    weave ctx, rest

  \refer-global : (ctx, { name }, rest) ->
    ctx.with \refer-global ->
      @statement do
        "if ( ! (genv.hasOwnProperty ( '#{name}' )) ) {
          throw 'undefined #{name}';
        }"
        "acc = genv['#{name}']"
    weave ctx, rest

  \indirect : (ctx, {}, rest) ->
    ctx.with \indirect ->
      @statement "acc = acc.value"
    weave ctx, rest

  \box : (ctx, { index }, rest) ->
    ctx.with \box ->
      @statement do
        "var $i = stack.length - #{index + 1}"
        "stack[$i] = new this.__cell__(stack[$i])"
    weave ctx, rest

  \constant : (ctx, { value }, rest) ->
    ctx.with \constant ->
      if rep = representation value
        @statement "acc = #{rep}"
      else
        p-name = @constant value
        @statement "acc = this.#{p-name}"
    weave ctx, rest

  \assign-local : (ctx, { index }, rest) ->
    ctx.with \assign-local ->
      @statement do
        "stack[frame - #{index}].value = acc"
        "acc = undefined"
    weave ctx, rest

  \assign-free : (ctx, { index }, rest) ->
    ctx.with \assign-free ->
      @statement do
        "env[ #{index} ].value = acc"
        "acc = undefined"
    weave ctx, rest

  \argument : (ctx, {}, rest) ->
    ctx.with \argument ->
      @statement "stack.push(acc)"
    weave ctx, rest

  \frame : (ctx, { return-to, proceed }) ->
    ctx.with \frame ->
      p-name = @constant link return-to
      @statement "stack.push(env, frame, this.#{p-name})"
    weave ctx, proceed

  \shift : (ctx, { keep, discard }, rest) ->
    ctx.with \shift ->
      if discard > 0
        @statement "stack.splice(stack.length - #{keep + discard}, #{discard})"
    weave ctx, rest

  \ret : (ctx, { discard }) ->
    ctx.with \ret ->
      if discard > 0
        @statement "stack.splice(stack.length - #{discard})"
      @statement do
        "regs.acc   = acc"
        "regs.fun   = stack.pop()"
        "regs.frame = stack.pop()"
        "regs.env   = stack.pop()"
      @finalize!

#  test = ((positive, negative) -> { op: test.op, positive, negative })
#    ..op = \test

  \close : (ctx, { free, arity, body }, rest) ->
    ctx.with \close ->
      p-name = @constant link body
      @statement do
        "var $newenv = []"
        "for ( var $i = 0; $i < #{free}; $i++ ) { $newenv.push (stack.pop ()); }"
        "acc = new this.__closure__ ( $newenv, #{arity}, this.#{p-name} )"
    weave ctx, rest

  \apply : (ctx, { args }) ->
    ctx.with \apply ->
      @statement do
        "if (! (acc instanceof this.__closure__) ) { throw 'not fun'; }"
        "if (! (acc.arity === #{args}) ) { throw 'arity mismatch'; }"
        "regs.fun   = acc.body"
        "regs.env   = acc.env"
        "regs.frame = stack.length - 1"
      @finalize!

  \apply-native : (ctx, { args }, rest) ->
    ctx.with \apply-native ->
      @statement do
        "if (! (acc instanceof Function) ) { throw 'not (native) fun' }"
        "var $args = []"
        "for ( var $i = 0; $i < #{args}; $i++ ) { $args.push(stack.pop ()); }"
        "acc = acc.apply(null, $args)"
    weave ctx, rest


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

console.log run do
  compiler.compile do
    [[\lambda [\x \y]
      [\set! \x [[\lambda [] [\native \+ \x \y]]]]
      \x]
     1 999]
  \+ : (a, b) -> a + b
