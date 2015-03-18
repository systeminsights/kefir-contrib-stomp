R = require 'ramda'
{head, last, runLog} = require 'kefir-contrib-run'
{Frame} = require 'stompjs'
{Some, None} = require 'fantasy-options'
{Left, Right} = require 'fantasy-eithers'
{subscribes, Transport, Config, StompError, FrameError} = require '../src/index'
socket = require './test-socket'

mkSocket = ->
  s = socket('ws://example.com/stomp')
  s.sent = s.sent.map((str) -> Frame.unmarshall(str)[0])
  s

cfg = (ws, hbSend, hbRecv) ->
  Config(Transport.Ws(ws), 'foo.example.com', hbSend, hbRecv, Some(login: 'baz', passcode: 'quux'))

nohbCfg = (ws) -> cfg(ws, 0, 0)

setup = ->
  sock = mkSocket()
  [sock, subscribes(nohbCfg(-> Right(sock.ws)))]

doAsync = (thunks) ->
  unless R.isEmpty(thunks)
    R.head(thunks)()
    process.nextTick(-> doAsync(R.tail(thunks)))

describe "subscribes", ->
  it "should emit Ws create error and end", ->
    err = new Error("Create failed")
    s = subscribes(nohbCfg(-> Left(err)))
    expect(head(s)).to.be.rejectedWith(StompError, /Create failed/)

  it "should connect to the server on activation", ->
    sock = mkSocket()
    hdrs = {host: 'foo.example.com', login: 'baz', passcode: 'quux'}
    hdrs = R.assoc('heart-beat', '5000,10000', hdrs)
    hdrs = R.assoc('accept-version', '1.1,1.0', hdrs)
    subs = subscribes(cfg((-> Right(sock.ws)), 5000, 10000))

    first = head(sock.sent)
    subs.onValue(->)
    process.nextTick(sock.emitOpen)

    expect(first).to.become(Some(new Frame('CONNECT', hdrs)))

  it "should gracefully disconnect from the server on deactivation", ->
    [sock, subs] = setup()
    f = ->

    dconn = last(sock.sent)
    subs.onValue(f)
    doAsync([sock.emitOpen, (-> subs.offValue(f))])

    expect(dconn).to.become(Some(new Frame('DISCONNECT')))

  it "should end when connection to server is closed", ->
    [sock, subs] = setup()

    fst = head(subs)
    doAsync([sock.emitOpen, sock.emitClose])

    expect(fst).to.become(None)

  it "should emit ERROR frames from the stomp server", ->
    [sock, subs] = setup()
    err = new Frame('ERROR', {}, 'Connection refused')

    lst = last(subs)
    doAsync([sock.emitOpen, (-> sock.emitMessage(err.toString())), sock.emitClose])

    expect(lst).to.be.rejected.and.eventually.be.an.instanceof(FrameError)

  it "should emit a function for subscribing to STOMP topics when connected", ->
    [sock, subs] = setup()
    hdrs = {version: '1.1'}
    hdrs['heart-beat'] = '0,0'
    conn = new Frame('CONNECTED', hdrs)

    lst = last(subs)
    doAsync([sock.emitOpen, (-> sock.emitMessage(conn.toString())), sock.emitClose])

    expect(lst).to.be.fulfilled.and.eventually.have.property('x').that.is.an.instanceof(Function)

  describe "subscribed stream", ->
    it "should subscribe to the stomp topic using the headers given on activation"

    it "should unsubscribe from the stomp topic on deactivation"

    it "should emit a Stomp.Frame for each message sent to the topic"

    it "should emit upstream errors"

    it "should not emit upstream errors for other subscriptions"

