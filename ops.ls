
halt = op: \halt

refer-local = (-> op: refer-local.op, index: it)
  ..op = \refer-local

refer-free = (-> op: refer-free.op, index: it)
  ..op = \refer-free

refer-global = (-> op: refer-global.op, name: it)
  ..op = \refer-global

indirect = op: \indirect

constant = (-> op: constant.op, value: it)
  ..op = \constant

close = ((free, arity, body) -> { op: close.op, free, arity, body })
  ..op = \close

box = (-> op: box.op, index: it)
  ..op = \box

test = (-> op: test.op, skip-if-not: it)
  ..op = \test

assign-local = (-> op: assign-local.op, index: it)
  ..op = \assign-local

assign-free = (-> op: assign-free.op, index: it)
  ..op = \assign-free

frame = (-> op: frame.op, return-after: it)
  ..op = \frame

argument = op: \argument

shift = ((keep, discard) -> { op: shift.op, keep, discard })
  ..op = \shift

apply = (-> op: apply.op, args: it)
  ..op = \apply

ret = (-> op: ret.op, discard: it)
  ..op = \ret

skip = (-> op: skip.op, skip: it)
  ..op = \skip

apply-native = (-> op: apply-native.op, args: it)
  ..op = \apply-native

#    conti        = \conti
#    nuate        = \nuate

module.exports = {
  halt , refer-local , refer-free , refer-global , indirect , constant , close
, box , test , assign-local , assign-free , frame , argument , shift
, apply , ret , skip, apply-native
}
