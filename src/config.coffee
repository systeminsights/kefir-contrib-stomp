{tagged, taggedSum} = require 'daggy'
{None} = require 'fantasy-options'

# The transport to use for STOMP.
Transport = taggedSum(
  # :: (String, Number) -> Transport
  #
  # TCP transport, accepts a hostname and port number to connect to.
  #
  Tcp: ['host', 'port'],

  # :: (-> Either Error WebSocket) -> Transport
  #
  # WebSocket transport, accepts a function that returns an Error or an object
  # that implements the WebSocket API. This function must not throw, return a
  # Left(Error) if creation of the WebSocket-like object fails.
  #
  Ws: ['create']
)

# :: (Transport, Number, Number, Option {username: String, password: String}) -> Config
#
# Configuration object for STOMP connections
#
# @param {Transport} transport
# @param {String} vhost the virtual host to connect to on the server
# @param {Number} hbSendFreqMillis frequency in milliseconds at which
#                                  to send heartbeats
# @param {Number} hbRecvFreqMillis requested frequency in milliseconds at which
#                                  heartbeats should be sent by the server
# @param {Option {login: String, passcode: String}} credentials
#        credentials to use for authentication, if None authentication is disabled
#
Config = tagged(
  'transport',
  'vhost',
  'hbSendFreqMillis',
  'hbRecvFreqMillis',
  'credentials'
)

# :: (Transport, String, Number, Number) -> Config
#
# Configuration that does not include authN credentials.
#
Config.noAuth = (transport, vhost, hbSendFreqMillis, hbRecvFreqMillis) ->
  Config(transport, vhost, hbSendFreqMillis, hbRecvFreqMillis, None)

module.exports = {Transport, Config}

