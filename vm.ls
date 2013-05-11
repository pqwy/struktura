
require! [\util \ops \prims]

pop-n = (s, n) ->
  for x from 0 til n then s.pop!

run = (bytecode, global-env = new ->) ->

  [ acc, code-p, code, frame, env, stack ] = [ void, 0, bytecode, 0, \noenv, [] ]

  loop
    instr = code[code-p]

#      console
#        ..log "loop:"
#        ..log " * acc:", acc
#        ..log " * ins:", instr
#        ..log " * stk:", stack

    switch instr.op

      case ops.halt.op =>
        return acc

      case ops.refer-local.op =>
        ++code-p
        acc := stack[frame - instr.index]

      case ops.refer-free.op =>
        ++code-p
        acc := env[instr.index]

      case ops.refer-global.op =>
        ++code-p
        if global-env.has-own-property instr.name
          acc := global-env[instr.name]
        else throw "undefined: #{instr.name}"

      case ops.indirect.op =>
        ++code-p
        acc := acc.value

      case ops.constant.op =>
        ++code-p
        acc := instr.value

      case ops.close.op =>
        ++code-p
        acc := new prims.Closure do
          (pop-n stack, instr.free), instr.arity, instr.body

      case ops.box.op =>
        ++code-p
        i = stack.length - 1 - instr.index
        stack[i] = new prims.Cell stack[i]

      case ops.test.op =>
        if acc is false
          code-p += instr.skip-if-not + 1
        else ++code-p

      case ops.skip.op =>
        code-p += instr.skip + 1

      case ops.assign-local.op =>
        ++code-p
        stack[frame - instr.index].value = acc
        acc := void

      case ops.assign-free.op =>
        ++code-p
        env[instr.index].value = acc
        acc := void

      case ops.frame.op =>
        ++code-p
        stack.push env, frame, code, (code-p + instr.return-after)

      case ops.argument.op =>
        ++code-p
        stack.push acc

      case ops.shift.op =>
        ++code-p
        stack.splice (stack.length - instr.keep - instr.discard), instr.discard

      case ops.apply.op =>
        if acc instanceof prims.Closure
          if acc.arity is instr.args
            code-p := 0
            code   := acc.body
            env    := acc.env
            frame  := stack.length - 1
          else throw "arity mismatch: have #{instr.args} want #{acc.arity}"
        else throw "not fun: #{util.inspect acc}"

      case ops.apply-native.op =>
        ++code-p
        if acc instanceof Function
          acc = acc.apply null, (pop-n stack, instr.args)
        else throw "not native fun: #{util.inspect acc}"

      case ops.ret.op =>
        stack.splice (stack.length - instr.discard)
        code-p := stack.pop!
        code   := stack.pop!
        frame  := stack.pop!
        env    := stack.pop!

#        case ops.conti.op =>
#        case ops.nuate.op =>
#        case ops.apply-native.op =>


      case _ => throw "bad instruction: #{instr}"


module.exports = { run }
