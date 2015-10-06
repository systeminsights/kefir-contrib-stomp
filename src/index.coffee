R = require 'ramda'
K = require 'kefir'
{Some, None} = require 'fantasy-options'
{Right} = require 'fantasy-eithers'
{foreach} = require 'fantasy-contrib-either'
{Stomp} = require 'stompjs/lib/stomp'
{Transport, Config} = require './config'

# Base type for STOMP-related errors
class StompError extends Error
  constructor: (@message, @cause) ->
    @name = 'StompError'

# An ERROR frame received from the server
class FrameError extends StompError
  constructor: (@frame) ->
    super(@frame.toString(), None)
    @name = 'FrameError'

# :: Confg -> Either StompError Stomp.Client
#
# Create a Stomp.Client on a live socket from the given Config.
#
clientFromConfig = (config) ->
  heartbeat =
    incoming: config.hbRecvFreqMillis
    outgoing: config.hbSendFreqMillis

  mkError = (wsErr) ->
    new StompError("Error creating socket: #{wsErr.message}", Some(wsErr))

  client = config.transport.cata(
    Tcp: (h, p) -> Right(Stomp.overTCP(h, p))
    Ws:  (ws)   -> ws().bimap(mkError, Stomp.over))

  foreach((c) ->
    c.debug     = false
    c.heartbeat = heartbeat
  )(client)

  client

# :: Kefir.Emitter -> (Stomp.Frame | String) -> ()
#
# Stomp.Client.connect onError callback. Connect will invoke this any time
# any error is sent from the server (an ERROR frame) and also if the connection
# closes unexpectedly (with a string message).
#
handleError = (emitter) -> (frameOrString) ->
  if frameOrString instanceof Stomp.Frame
    emitter.error(new FrameError(frameOrString))
  else
    emitter.end()

# :: Property StompError Boolean -> Stomp.Client -> PubSub
pubSub = R.curry (connected, client) ->
  mkError = (action, headers, destination, cause) ->
    new StompError(
      "#{action} failed: #{cause.message}, destination=#{destination}, headers=#{JSON.stringify(headers)}",
      Some(cause))

  subscribe = R.curry (headers, destination) ->
    frames = K.fromBinder (emitter) ->
      try
        # NB: This will throw if called while the client is disconnected
        # NB: https://github.com/jmesnil/stomp-websocket/issues/107
        sub = client.subscribe(destination, emitter.emit, R.merge({}, headers))
        sub.unsubscribe
      catch err
        emitter.error(mkError("Subscribe", headers, destination, err))
        emitter.end()
        R.always(undefined)

    frames .takeWhileBy connected

  publish = R.curry (headers, destination) ->
    sink = K.fromBinder (emitter) ->
      pub = (body) -> () ->
        try
          client.send(destination, R.merge({}, headers), body)
        catch err
          emitter.error(mkError("Publish", headers, destination, err))
          emitter.end()

      emitter.emit(pub)
      undefined

    connected
      .flatMapLatest((isConnected) -> if isConnected then sink.toProperty() else K.never())
      .toProperty()

  {publish, subscribe}

# :: Config -> Property Error PubSub
#
# Returns a property of a PubSub object for interacting with STOMP
#
# type PubSub =
#   subscribe :: Headers -> String -> Kefir StompError Stomp.Frame
#   publish   :: Headers -> String -> Property StompError (String -> () -> ())
#
# `subscribe` accepts a header object and a destination and returns a stream
# of Stomp.Frames sent to that destination. `publish` accepts a header object
# and a destination and returns a property of a publisher function. This function
# accepts the string body to publish to the destination and returns a thunk which,
# when forced, will send the message.
#
# Errors are emitted for connection issues as well as STOMP errors during
# operation.
#
pubSubs = (config) ->
  headers = config.credentials.fold(R.merge, -> R.identity)({host: config.vhost})

  clients = K.fromBinder (emitter) ->
    clientFromConfig(config).fold(
      ((err) ->
        emitter.error(err)
        emitter.end()
        R.always(undefined)),
      ((client) ->
        # NB: https://github.com/jmesnil/stomp-websocket/issues/107
        client.connect(R.merge({}, headers), (-> emitter.emit(client)), handleError(emitter))
        client.disconnect.bind(client)))

  connected = clients.map(R.always(true)).mapEnd(R.always(false)).toProperty(true)
  clients.map(pubSub(connected)).toProperty()

module.exports = {pubSubs, Transport, Config, StompError, FrameError}
