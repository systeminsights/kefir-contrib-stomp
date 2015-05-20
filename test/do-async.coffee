R = require 'ramda'

doAsync = (thunks) ->
  setImmediate(->
    unless R.isEmpty(thunks)
      R.head(thunks)()
      doAsync(R.tail(thunks)))

module.exports = doAsync

