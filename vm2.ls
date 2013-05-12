

require! [\util \ops \prims]

pop-n = (s, n) ->
  [ s.pop! for x from 0 til n ]

class HaltExn

vop =

  "#{ops.halt.op}":
    class halt
      invoke: !-> throw new HaltExn

  "#{ops.refer-local.op}":
    class refer-local
      ({ @index }) ->
      invoke: !->
        ++it.code-p
        it.acc = it.stack[it.frame - @index]

  "#{ops.refer-free.op}":
    class refer-free
      ({ @index }) ->
      invoke: !->
        ++it.code-p
        it.acc = it.env[@index]

  "#{ops.refer-global.op}":
    class refer-global
      ({ @name }, @global-env) ->
      invoke: !->
        ++it.code-p
        if @global-env.has-own-property @name
          it.acc = @global-env[@name]
        else throw "undefined: #{@name}"

  "#{ops.indirect.op}":
    class indirect
      invoke: !->
        ++it.code-p
        it.acc = it.acc.value

  "#{ops.constant.op}":
    class constant
      ({ @value }) ->
      invoke: !->
        ++it.code-p
        it.acc = @value

  "#{ops.close.op}":
    class close
      ({ @free, @arity, body }, global-env) ->
        @body = prepare body, global-env
      invoke: !->
        ++it.code-p
        it.acc = new prims.Closure (pop-n it.stack, @free), @arity, @body

  "#{ops.box.op}":
    class box
      ({ @index }) ->
      invoke: !->
        ++it.code-p
        i = it.stack.length - 1 - @index
        it.stack[i] = new prims.Cell it.stack[i]

  "#{ops.test.op}":
    class test
      ({ @skip-if-not }) ->
      invoke: !->
        if it.acc is false
          it.code-p += @skip-if-not + 1
        else ++it.code-p

  "#{ops.skip.op}":
    class skip
      ({ @skip }) ->
      invoke: !->
        it.code-p += @skip + 1

  "#{ops.assign-local.op}":
    class assign-local
      ({ @index }) ->
      invoke: !->
        ++it.code-p
        it.stack[it.frame - @index].value = it.acc
        it.acc = void

  "#{ops.assign-free.op}":
    class assign-free
      ({ @index }) ->
      invoke: !->
        ++it.code-p
        it.env[@index].value = it.acc
        it.acc = void

  "#{ops.frame.op}":
    class frame
      ({ @return-after }) ->
      invoke: !->
        ++it.code-p
        it.stack.push it.env, it.frame, it.code, (it.code-p + @return-after)

  "#{ops.argument.op}":
    class argument
      invoke: !->
        ++it.code-p
        it.stack.push it.acc

  "#{ops.shift.op}":
    class shift
      ({ @keep, @discard }) ->
      invoke: !->
        ++it.code-p
        it.stack.splice (it.stack.length - @keep - @discard), @discard

  "#{ops.apply.op}":
    class apply
      ({ @args }) ->
      invoke: !->
        if it.acc instanceof prims.Closure
          if it.acc.arity is @args
            it.code-p = 0
            it.code   = it.acc.body
            it.env    = it.acc.env
            it.frame  = it.stack.length - 1
          else throw "arity mismatch: have #{instr.args} want #{acc.arity}"
        else throw "not fun: #{util.inspect acc}"

  "#{ops.apply-native.op}":
    class apply-native
      ({ @args }) ->
      invoke: !->
        ++it.code-p
        if it.acc instanceof Function
          it.acc = it.acc.apply null, (pop-n it.stack, @args)
        else throw "not native fun: #{util.inspect acc}"

  "#{ops.ret.op}":
    class ret
      ({ @discard }) ->
      invoke: !->
        it.stack.splice (it.stack.length - @discard)
        it.code-p = it.stack.pop!
        it.code   = it.stack.pop!
        it.frame  = it.stack.pop!
        it.env    = it.stack.pop!

prepare = (bytecode, global-env = new ->) ->
  bytecode.map (instr) ->
    new vop[instr.op] instr, global-env

run-prepared = (threaded) ->

  regs =
    acc    : void
    code-p : 0
    code   : threaded
    frame  : 0
    env    : \noenv
    stack  : []

  try
    loop
      regs.code[regs.code-p].invoke regs

  catch e
    unless e instanceof HaltExn
      console
        ..log ":: unhandled exn ::"
        ..log "  ", e
        ..log regs
      throw e

  regs.acc

run = (bytecode, global-env = new ->) ->
  prep = prepare bytecode, global-env
  run-prepared prep


module.exports = { run, prepare, run-prepared }