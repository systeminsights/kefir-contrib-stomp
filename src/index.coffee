R = require 'ramda'
K = require 'kefir'
{Some, None} = require 'fantasy-options'
{Right} = require 'fantasy-eithers'
{foreach} = require 'fantasy-contrib-either'
Stomp = require 'stompjs'
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
stompFromConfig = (config) ->
  heartbeat =
    incoming: config.hbRecvFreqMillis
    outgoing: config.hbSendFreqMillis

  mkError = (wsErr) ->
    new StompError("Error creating socket: #{wsErr.message}", Some(wsErr))

  stompClient = config.transport.cata(
    Tcp: (h, p) -> Right(Stomp.overTCP(h, p))
    Ws:  (ws)   -> ws().bimap(mkError, Stomp.over))

  foreach((c) ->
    c.debug     = false
    c.heartbeat = heartbeat
  )(stompClient)

  stompClient

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

# :: Config -> Property StompError Client
#
# Returns a property of a `Client` which may be used to send and subscribe to
# Stomp messages. The `Client` has the following properties
#
#   type Destination = String
#   type Headers = Object
#   type Body = String
#   type OnFrame = Stomp.Frame -> ()
#
#   connected :: Property StompError Boolean -- whether the client is connected to the server
#   publish :: Destination -> Headers -> Body -> () -- publish the body to the specified Stomp destination
#   subscribe :: Destination -> Headers -> OnFrame -> SubId -- subscribe to messages from the destination
#   unsubscribe :: SubId -> () -- cancel the subscription represented by the given `SubId`
#
clients = (config) ->
  headers = config.credentials.fold(R.merge, -> R.identity)({host: config.vhost})

  clientFromStomp = (stomp) ->
    # NB: We initialize the property with `true` as we only create the client on successful connect
    connected:   clientStream.map(R.always(true)).mapEnd(R.always(false)).toProperty(true)
    publish:     stomp.send.bind(stomp)
    # NB: https://github.com/jmesnil/stomp-websocket/issues/107
    subscribe:   (dest, hdrs, onMsg) -> stomp.subscribe(dest, onMsg, R.merge({}, hdrs))
    unsubscribe: stomp.unsubscribe.bind(stomp)

  clientStream = K.fromBinder (emitter) ->
    stompFromConfig(config).fold(
      ((err) ->
        emitter.error(err)
        emitter.end()
        R.always(undefined)),
      ((stomp) ->
        # NB: https://github.com/jmesnil/stomp-websocket/issues/107
        stomp.connect(R.merge({}, headers), (-> emitter.emit(clientFromStomp(stomp))), handleError(emitter))
        stomp.disconnect.bind(stomp)))

  clientStream

# :: Client -> Object -> String -> Kefir StompError Stomp.Frame
#
# Given a `Client` (as provided by the `clients` function), subscription headers
# and a destination, returns a stream of `Stomp.Frame`s published to the destination.
#
# The resulting stream will end if the client becomes disconnected.
#
frames = R.curry (client, headers, destination) ->
  frameStream = K.fromBinder (emitter) ->
    try
      # NB: This will throw if called while the client is disconnected
      subId = client.subscribe(destination, headers, emitter.emit)
      () -> client.unsubscribe(subId)
    catch err
      emitter.error(new StompError(
        "Subscribe failed: #{err.message}, destination=#{destination}, headers=#{JSON.stringify(headers)}",
        Some(err)))
      emitter.end()
      R.always(undefined)

  frameStream .takeWhileBy client.connected

module.exports = {clients, frames, Transport, Config, StompError, FrameError}

