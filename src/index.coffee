R = require 'ramda'
K = require 'kefir'
{Some, None} = require 'fantasy-options'
{Right} = require 'fantasy-eithers'
{foreach} = require 'fantasy-contrib-either'
Stomp = require 'stompjs'
{Transport, Config} = require './config'

# type Subscribe = Headers -> String -> Kefir Error Stomp.Frame
#
# Given subscribe headers and a STOMP destination, returns a stream of
# Stomp.Frames representing the messages published to the destination.

# Possible Error types
#
# StompError
#   ConnectError (proto negotiation failed, else?)
#   AuthError
#   FrameError ??
#
# Any other validation-y errors?

class StompError extends Error
  constructor: (@message, @cause) ->
    @name = 'StompError'

class FrameError extends StompError
  constructor: (@frame) ->
    super(@frame.toString(), None)
    @name = 'FrameError'

# :: Confg -> Either StompError Stomp.Client
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

# :: (-> Option String) -> StompError -> Boolean
relatedToSub = (subId) -> (err) ->
  if err instanceof FrameError
    headers = err.frame.headers
    if R.has('subscription', headers)
      subId().fold(R.eq(headers.subscription), -> true)
    else
      true
  else
    true

# :: Stomp.Client -> Object -> String -> Kefir StompError Stomp.Frame
subscribe = R.curry((client, headers, destination) ->
  subId = None

  K.fromBinder((emitter) ->
    try
      # NB: This will throw if called while the client is disconnected
      sub = client.subscribe(destination, emitter.emit, headers)
      subId = Some(sub.id)
      sub.unsubscribe
    catch err
      emitter.error(new StompError(
        "Subscribe failed: #{err.message}, destination=#{destination}, headers=#{JSON.stringify(headers)}",
        Some(err)))
      emitter.end()
      R.always(undefined)
  ).filterError(relatedToSub(-> subId)))

# :: Config -> Property Error Subscribe
#
# Returns a stream of functions for subscribing to a STOMP destination.
#
# Errors are emitted for connection issues as well as STOMP errors during
# operation.
#
# TODO: What types of errors does STOMP emit? Do we want to swallow any of them
#       (i.e. spurious unsubscribes?) To start with, just be conservative and restart
#       on any error, we can pare this down if it becomes too frequent.
#
subscribes = (config) ->
  headers = config.credentials.fold(R.merge, -> R.identity)({host: config.vhost})

  K.fromBinder((emitter) ->
    clientFromConfig(config).fold(
      ((err) ->
        emitter.error(err)
        emitter.end()
        R.always(undefined)),
      ((client) ->
        client.connect(headers, (-> emitter.emit(client)), handleError(emitter))
        client.disconnect.bind(client)))
  ).map(subscribe).toProperty()

module.exports = {subscribes, Transport, Config, StompError, FrameError}

