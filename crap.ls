
merge = (...dicts) ->
# fuck you, livescript
#    {[k, v] for d in dicts for k, v of d}
  o = {}
  for d in dicts then for k, v of d then o[k] = v
  o

appends = (...arrs) -> [].concat ...arrs

compose-r = (fs) -> (x) ->
  for f in reverse fs then x = f x
  x

compose-l = (fs) -> compose ...fs

init = (xs) -> xs[0 til xs.length - 1]

intercalate = (e, arr) ->
  r = []
  for i from 0 til arr.length - 1 then r.push arr[i], e
  r.push arr[arr.length - 1]
  r

module.exports = { merge, appends, compose-r, compose-l, init, intercalate }

