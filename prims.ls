
class SCM then

class Closure extends SCM
  (@env, @arity, @body) ->

class Cell extends SCM
  (@value) ->

class Cons extends SCM
  (@car, @cdr) ->

read-string = (str) ->

module.exports = { SCM, Closure, Cell }

