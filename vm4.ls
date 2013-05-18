
require! \./prims

class module-ctx
  ->
    [ @uniq, @entry, @cpool, @blocks ] = [ 0, void, {}, {} ]

  constant : (x) ->
    switch typeof! x
      case \String    => "\"#{x}\""
      case \Number    => "#{x}"
      case \Boolean   => "#{x}"
      case \Null      => "null"
      case \Undefined => "undefined"
      case _ => throw new Error "constant not representable: #{x}"
#      c-name = "__c__#{@uniq++}"
#      @cpool[c-name] = v
#      c-name

  link-block : (bc, next-block) ->
    b-name = "__b__#{@uniq++}"
    @entry ||= b-name
    ( @blocks[b-name] = new block @ )
      ..link-stream bc, next-block
    b-name

  get-c-text : (x) ->
    switch typeof! x
      case \String    => "\"#{x}\""
      case \Number    => "#{x}"
      case \Boolean   => "#{x}"
      case \Null      => "null"
      case \Undefined => "undefined"
      case _ => throw new Error "link: constant not representable: #{x}"

  get-b-text : (blk) ->
    """( function (regs, genv) {
  var stack = regs.stack ,
  env   = regs.env   ,
  acc   = regs.acc   ,
  frame = regs.frame ,
  fun   = regs.fun   ;
#{ blk.fragments.join '' }
})"""

  get-text : ->
    """
( function (prims) {
  const __closure__ = prims.Closure;
  const __cell__    = prims.Cell;
#{ [ "const #{n} = #{@get-c-text v};" for n, v of @cpool ].join '\n' }
#{ [ "const #{n} = #{@get-b-text v};" for n, v of @blocks ].join '\n' }
  return { 'enter': #{@entry} };
} )"""

  link : (bc, env) ->
    @link-block bc, void
    res = @get-text!
    console
      ..log "[link]\n"
      ..log res
      ..log "\n[/link]"
    res


class block

  (@module) -> @fragments = []

  line      : (...xs) -> @emit ...xs, -> "  #{it}\n"
  statement : (...xs) -> @emit ...xs, -> "  #{it};\n"
  note      : (...xs) -> @emit ...xs, -> "\n  // #{it} \n"

  emit : (...frgs, f) ->
    @fragments.push ...[ f frg for frg in frgs ] ; @

  link-stream : (bc, next-block) ->

    :stream for {op: instr}:op, i in bc

      @note instr

      switch instr

        case \halt =>
          @statement do
            "regs.acc = acc"
            "throw 'halt'"

        case \refer-local =>
          @statement "acc = stack[frame - #{op.index}]"

        case \refer-free =>
          @statement "acc = env[ #{op.index} ]"

        case \refer-global =>
          @statement do
            "if ( ! (genv.hasOwnProperty ( '#{op.name}' )) ) {
              throw 'undefined global: \"#{op.name}\"';
            }"
            "acc = genv['#{op.name}']"

        case \indirect =>
          @statement "acc = acc.value"

        case \box =>
          @statement do
            "var $i = stack.length - #{op.index + 1}"
            "stack[$i] = new __cell__(stack[$i])"

        case \constant =>
          @statement "acc = #{@module.constant op.value}"

        case \assign-local =>
          @statement do
            "stack[frame - #{op.index}].value = acc"
            "acc = undefined"

        case \assign-free =>
          @statement do
            "env[ #{op.index} ].value = acc"
            "acc = undefined"

        case \argument =>
          @statement "stack.push(acc)"

        case \frame =>
          f-name = @module.link-block op.return-to, next-block
          next-block := void
          @statement "stack.push(env, frame, #{f-name})"
          @link-stream op.proceed, void

        case \shift =>
          if op.discard > 0
            @statement do
              "stack.splice(stack.length - #{op.keep + op.discard}, #{op.discard})"

        case \ret =>
          if op.discard > 0
            @statement "stack.splice(stack.length - #{op.discard})"
          @statement do
            "regs.acc   = acc"
            "regs.fun   = stack.pop()"
            "regs.frame = stack.pop()"
            "regs.env   = stack.pop()"
            "return"

        case \test =>
          join = @module.link-block bc[i + 1 to ], next-block
          next-block := void

          @line "if (acc != false) {"
          @link-stream op.positive, join
          @line "} else {"
          @link-stream op.negative, join
          @line "}"

          break stream

        case \close =>
          f-name = @module.link-block op.body, void
          @statement "var $newenv = []"
          if op.free > 0
            @statement do
              "for ( var $i = 0; $i < #{op.free}; $i++ ) { $newenv.push (stack.pop ()); }"
          @statement do
            "acc = new __closure__ ( $newenv, #{op.arity}, #{f-name} )"

        case \apply =>
          @statement do
            "if (! (acc instanceof __closure__) ) { throw 'not fun'; }"
            "if (! (acc.arity === #{op.args}) ) { throw 'arity mismatch'; }"
            "regs.fun   = acc.body"
            "regs.env   = acc.env"
            "regs.frame = stack.length - 1"
            "return"

        case \apply-native =>
          @statement do
            "if (! (acc instanceof Function) ) { throw 'not (native) fun' }"
            "var $args = []"
            "for ( var $i = 0; $i < #{op.args}; $i++ ) { $args.push(stack.pop ()); }"
            "acc = acc.apply(null, $args)"

    if next-block?
      @note \connect-block
      @statement do
        "regs.fun = #{next-block}"
        "regs.acc = acc"


link = (bc, env) -> new module-ctx!link bc, env

scrubbed-eval = (str) -> eval str

run-linked = (op, env) ->

  regs =
    acc   : void
    fun   : (scrubbed-eval op) prims .enter
    frame : 0
    env   : \noenv
    stack : []

  try
    loop
#        console
#          ..log "invoke -->"
#          ..log "    ", regs.fun
      regs.fun regs, env

  catch e
    unless e is \halt
      console
        ..log ":: unhandled exn ::"
        ..log "  ", e
        ..log regs
      throw e

  regs.acc

run = (bc, env = new ->) ->
  run-linked (link bc, env), env

module.exports = { link, run-linked, run }
