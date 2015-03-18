R = require 'ramda'
K = require 'kefir'
{Some, None} = require 'fantasy-options'
{Right} = require 'fantasy-eithers'
{foreach} = require 'fantasy-contrib-either'
Stomp = require 'stompjs'
{Transport, Config} = require './config'

# type Subscribe = Headers -> String -> Kefir StompError Stomp.Frame
#
# Given subscribe headers and a STOMP destination, returns a stream of
# Stomp.Frames representing the messages published to the destination.

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

# :: Kefir _ Boolean -> Stomp.Client -> Object -> String -> Kefir StompError Stomp.Frame
subscribe = R.curry((connected, client, headers, destination) ->
  frames = K.fromBinder((emitter) ->
    try
      # NB: This will throw if called while the client is disconnected
      # NB: https://github.com/jmesnil/stomp-websocket/issues/107
      sub = client.subscribe(destination, emitter.emit, R.merge({}, headers))
      sub.unsubscribe
    catch err
      emitter.error(new StompError(
        "Subscribe failed: #{err.message}, destination=#{destination}, headers=#{JSON.stringify(headers)}",
        Some(err)))
      emitter.end()
      R.always(undefined))

  frames .takeWhileBy connected)

# :: Config -> Property Error Subscribe
#
# Returns a stream of functions for subscribing to a STOMP destination.
#
# Errors are emitted for connection issues as well as STOMP errors during
# operation.
#
subscribes = (config) ->
  headers = config.credentials.fold(R.merge, -> R.identity)({host: config.vhost})

  subs = K.fromBinder((emitter) ->
    clientFromConfig(config).fold(
      ((err) ->
        emitter.error(err)
        emitter.end()
        R.always(undefined)),
      ((client) ->
        # NB: https://github.com/jmesnil/stomp-websocket/issues/107
        client.connect(R.merge({}, headers), (-> emitter.emit(client)), handleError(emitter))
        client.disconnect.bind(client))))

  connected = subs.mapTo(true).mapEnd(R.always(false)).toProperty(true)
  subs.map(subscribe(connected)).toProperty()

module.exports = {subscribes, Transport, Config, StompError, FrameError}

