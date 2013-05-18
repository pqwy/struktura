
require! [\util \./compiler \./prims \./vm1 \./vm2 \./vm3 \./vm4]

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
  \*    : (a, b) -> a * b
  \=    : (a, b) -> a is b
  \cons : (a, b) -> new prims.Cons a, b
  \car  : -> it.car
  \cdr  : -> it.cdr

evaluate do
#    [[\lambda [\a]
#      [\if false
#        [[\lambda [] [\set! \a [\native \+ \a 10]]]]
#        [[\lambda [] [\set! \a [\native \+ \a 1 ]]]]]
#      [\if true
#        [[\lambda [] [\set! \a [\native \* \a 3]] \a]]
#        [[\lambda [] [\set! \a [\native \* \a 5]] \a]]]]
#     1]
  [[\lambda [\f]
    [\set! \f
      [\lambda [\a \n]
        [\if [\native \= \n 30001] \a
          [\f [\native \+ \a \n] [\native \+ \n 1]]]]]
    [\f 0 0]]
   void]
  vm4
  e

#  show compiler.compile do
#  #    [[\lambda [\f]
#  #      [\set! \f
#  #        [\lambda [\a \n]
#  #          [\if [\native \= \n 30001] \a
#  #            [\f [\native \+ \a \n] [\native \+ \n 1]]]]]
#  #      [\f 0 0]]
#  #     void]
#    [[\lambda [\a]
#      [\if false
#        [[\lambda [] [\set! \a [\native \+ \a 10]]]]
#        [[\lambda [] [\set! \a [\native \+ \a 1 ]]]]]
#      [\if true
#        [[\lambda [] [\set! \a [\native \* \a 3]]]]
#        [[\lambda [] [\set! \a [\native \* \a 5]]]]]
#      \a] 1]

