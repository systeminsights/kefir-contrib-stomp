R = require 'ramda'

# :: [-> ()] -> ()
#
# Executes an array of thunks asynchronously, each one at the `nextTick` of the
# process.
#
doAsync = (thunks) ->
  setImmediate(->
    unless R.isEmpty(thunks)
      R.head(thunks)()
      doAsync(R.tail(thunks)))

module.exports = doAsync

