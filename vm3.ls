
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

  statement: -> @fragments.push it ; @

  constant : (v) ->
    p-name = "__constant__#{@uniq++}"
    @props[p-name] = v
    p-name

  finalize: ->
    code = "
    ( function (regs, genv) {    \n
        var stack = regs.stack , \n
            env   = regs.env   , \n
            acc   = regs.acc   , \n
            frame = regs.frame , \n
            fun   = regs.fun   ; \n
        #{ [ f ++ ';' for f in @fragments ].join '\n' } \n
      }
    )"

    vop =
      invoke      : sanitized-eval code
      __closure__ : prims.Closure
      __cell__    : prims.Cell

    for pn, pv of @props then vop[pn] = pv

    console
      ..log '>>>'
      ..log '', vop.invoke
      ..log '<<<'
    vop

  dump: (op) ->
    @statement "console.log ( '[DUMP] #{op}', stack, env, acc, frame )"

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
    ctx
      .statement " regs.acc = acc ; throw 'halt' "
      .finalize!

  \refer-local : (ctx, { index }, rest) ->
    ctx.statement " acc = stack[frame - #{index}] "
    weave ctx, rest

  \refer-free  : (ctx, { index }, rest) ->
    ctx.statement " acc = env[ #{index} ] "
    weave ctx, rest

  \refer-global : (ctx, { name }, rest) ->
    ctx
      .statement "
      if ( ! genv.hasOwnProperty ( '#{name}' ) ) {
        throw 'undefined #{name}';
      }"
      .statement " acc = genv[ '#{name}' ] "
    weave ctx, rest

  \indirect : (ctx, {}, rest) ->
    ctx.stack " acc = acc.value "
    weave ctx, rest

  \box : (ctx, { index }, rest) ->
    ctx.statement " stack[ #{index} ] = new this.__cell__ ( stack[ #{index} ] ) "
    weave ctx, rest

  \constant : (ctx, { value }, rest) ->
    if rep = representation value
      ctx.statement " acc = #{rep} "
    else
      p-name = ctx.constant value
      ctx.statement " acc = this.#{p-name} "
    weave ctx, rest

  \assign-local : (ctx, { index }, rest) ->
    ctx
      .statement " stack[ frame - #{index} ] = acc "
      .statement " acc = undefined "
    weave ctx, rest

  \assign-free : (ctx, { index }, rest) ->
    ctx
      .statement " env[ #{index} ].value = acc "
      .statement " acc = undefined "
    weave ctx, rest

  \argument : (ctx, {}, rest) ->
    ctx.statement " stack.push ( acc ) "
    weave ctx, rest

  \frame : (ctx, { return-to, proceed }) ->
    p-name = ctx.constant link return-to
    ctx.statement " stack.push ( env, frame, this.#{p-name} ) "
    weave ctx, proceed

  \shift : (ctx, { keep, discard }, rest) ->
    ctx.statement do
      " stack.splice ( stack.length - #{keep} - #{discard}, #{discard} ) "
    weave ctx, rest

  \ret : (ctx, { discard }) ->
    ctx
      .statement " stack.splice ( stack.length - #{discard} ) "
      .statement " regs.acc   = acc "
      .statement " regs.fun   = stack.pop () "
      .statement " regs.frame = stack.pop () "
      .statement " regs.env   = stack.pop () "
      .finalize!

#  test = ((positive, negative) -> { op: test.op, positive, negative })
#    ..op = \test

  \close : (ctx, { free, arity, body }, rest) ->
    p-name = ctx.constant link body
    ctx
      .statement " var $newenv = [] "
      .statement " for ( var i = 0; i < #{free}; i++ ) { $newenv.push (stack.pop ()); } "
      .statement " acc = new this.__closure__ ( $newenv, #{arity}, this.#{p-name} ) "
    weave ctx, rest

  \apply : (ctx, { args }) ->
    ctx
      .statement "if (! acc instanceof this.__closure__) { throw 'not fun'; } "
      .statement "if (! acc.arity === #{args}) { throw 'arity mismatch'; } "
      .statement " regs.fun = acc.body "
      .statement " regs.env = acc.env "
      .statement " regs.frame = stack.length - 1 "
      .finalize!

  \apply-native : (ctx, { args }, rest) ->
    ctx
      .statement " if (! acc instanceof Function) { throw 'not (native) fun' } "
      .statement " var $args = [] "
      .statement " for ( var i = 0; i < #{args}; i++ ) { $args.push (stack.pop ()); } "
      .statement " acc = acc.apply ( null, $args ) "
    weave ctx, rest


run-linked = (op, genv) ->

  regs =
    acc   : void
    fun   : op
    frame : 0
    env   : \noenv
    stack : []

  try
    loop
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
      [[\lambda [] \y]]]
     11 12]
  a: 19
