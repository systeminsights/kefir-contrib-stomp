K = require 'kefir'
{EventEmitter} = require 'events'

# A fixture for testing interactions with a WebSocket-like object.
#
# ws: The WebSocket like object, supports all the methods and event listeners
#     in the WebSocket API.
#
# sent: A Kefir stream of the data emitted via ws.send()
#
# emitClose: Trigger the 'close' event, also ends the sent stream
#
# emitError: Trigger the 'error' event
#
# emitOpen: Trigger the 'open' event
#
# emitMessage: Trigger the 'message' event with the given data
#
module.exports = (url) ->
  sent = K.emitter()
  ee = new EventEmitter

  emitClose = ->
    sent.end()
    ee.emit('close', {code: -1, reason: 'TEST', wasClean: true})

  emitError = ->
    ee.emit('error', 'error')

  emitOpen = ->
    ee.emit('open', 'open')

  emitMessage = (data) ->
    ee.emit('message', {data})

  ws =
    url: url,
    send: sent.emit.bind(sent),
    close: emitClose

  ee.on('close', (c) -> ws.onclose?(c))
  ee.on('error', (e) -> ws.onerror?(e))
  ee.on('open', (o) -> ws.onopen?(o))
  ee.on('message', (m) -> ws.onmessage?(m))

  {emitClose, emitError, emitOpen, emitMessage, sent, ws}

