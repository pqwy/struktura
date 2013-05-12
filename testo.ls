
require! [\util \./compiler \./prims \./vm \./vm2]

show = (...xs, x) ->
  console.log ...xs, util.inspect x, {+colors, depth: null}

time = (tag, f) ->
  t0  = new Date
  res = f!
  t1  = new Date
  console.log "[time] #{tag} #{t1 - t0} ms"
  res

evaluate = (code, vm, env = new ->) ->
  bc = time "compile" -> compiler.compile code
  show bc
  ln  = vm.link bc, env
  res = time "vm", -> vm.run-linked ln, env
  show res

e =
  \+    : (a, b) -> a + b
  \=    : (a, b) -> a is b
  \cons : (a, b) -> new prims.Cons a, b
  \car  : -> it.car
  \cdr  : -> it.cdr

evaluate do
  [[\lambda [\f]
    [\set! \f
      [\lambda [\a \n]
        [\if [\native \= \n 30001] \a
          [\f [\native \+ \a \n] [\native \+ \n 1]]]]]
    [\f 0 0]]
   void]
  vm2
  e

#  show compiler.compile do
#    [[\lambda [\f]
#      [\set! \f
#        [\lambda [\a \n]
#          [\if [\native \= \n 30001] \a
#            [\f [\native \+ \a \n] [\native \+ \n 1]]]]]
#      [\f 0 0]]
#     void]
