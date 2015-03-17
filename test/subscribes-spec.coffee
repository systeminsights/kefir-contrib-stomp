R = require 'ramda'
{head, runLog} = require 'kefir-contrib-run'
{Frame} = require 'stompjs'
{Some} = require 'fantasy-options'
{Left, Right} = require 'fantasy-eithers'
{subscribes, Transport, Config, StompError} = require '../src/index'
socket = require './test-socket'

mkSocket = ->
  s = socket('ws://example.com/stomp')
  s.sent = s.sent.map((str) -> Frame.unmarshall(str)[0])
  s

cfg = (ws) ->
  Config(Transport.Ws(ws), 'foo.example.com', 5000, 10000, Some(login: 'baz', passcode: 'quux'))

describe "subscribes", ->
  it "should emit Ws create error and end", ->
    err = new Error("Create failed")
    s = subscribes(cfg(-> Left(err)))
    expect(head(s)).to.be.rejectedWith(StompError, /Create failed/)

  it "should connect to the server on activation", ->
    sock = mkSocket()
    hdrs = {host: 'foo.example.com', login: 'baz', passcode: 'quux'}
    hdrs = R.assoc('heart-beat', '5000,10000', hdrs)
    hdrs = R.assoc('accept-version', '1.1,1.0', hdrs)
    subs = subscribes(cfg(-> Right(sock.ws)))

    first = head(sock.sent)
    subs.onValue(->)
    process.nextTick(sock.emitOpen)

    expect(first).to.become(Some(new Frame('CONNECT', hdrs)))

  it "should gracefully disconnect to the server on deactivation"

  it "should end when connection to server is closed"

  it "should emit ERROR frames from the stomp server"

  it "should emit a function for subscribing to STOMP topics"

  describe "subscribed stream", ->
    it "should subscribe to the stomp topic using the headers given on activation"

    it "should unsubscribe from the stomp topic on deactivation"

    it "should emit a Stomp.Frame for each message sent to the topic"

    it "should emit upstream errors"

    it "should not emit upstream errors for other subscriptions"

