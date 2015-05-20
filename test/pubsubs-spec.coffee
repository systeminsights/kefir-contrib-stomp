R = require 'ramda'
K = require 'kefir'
{head, last, runLog, runLogValues} = require 'kefir-contrib-run'
{Frame} = require 'stompjs'
{Some, None} = require 'fantasy-options'
{Left, Right} = require 'fantasy-eithers'
{pubSubs, Transport, Config, StompError, FrameError} = require '../src/index'
socket = require './test-socket'
doAsync = require './do-async'

mkSocket = ->
  s = socket('ws://example.com/stomp')
  s.sent = s.sent.map((str) -> Frame.unmarshall(str)[0])
  s

cfg = (ws, hbSend, hbRecv) ->
  Config(Transport.Ws(ws), 'foo.example.com', hbSend, hbRecv, Some(login: 'baz', passcode: 'quux'))

nohbCfg = (ws) ->
  cfg(ws, 0, 0)

setup = ->
  sock = mkSocket()
  [sock, pubSubs(nohbCfg(-> Right(sock.ws)))]

emitFrame = (sock, frame) -> () ->
  sock.emitMessage(frame.toString())

connected = ->
  hdrs = {version: '1.1'}
  hdrs['heart-beat'] = '0,0'
  new Frame('CONNECTED', hdrs)

emitConnected = (sock) ->
  emitFrame(sock, connected())

describe "pubSubs", ->
  it "should emit Ws create error and end", ->
    err = new Error("Create failed")
    ps = pubSubs(nohbCfg(-> Left(err)))
    expect(head(ps)).to.be.rejectedWith(StompError, /Create failed/)

  it "should connect to the server on activation", ->
    sock = mkSocket()
    hdrs = {host: 'foo.example.com', login: 'baz', passcode: 'quux'}
    hdrs = R.assoc('heart-beat', '5000,10000', hdrs)
    hdrs = R.assoc('accept-version', '1.1,1.0', hdrs)
    ps = pubSubs(cfg((-> Right(sock.ws)), 5000, 10000))

    doAsync [
      (-> ps.onValue(->))
      sock.emitOpen
    ]

    expect(head(sock.sent)).to.become(Some(new Frame('CONNECT', hdrs)))

  it "should gracefully disconnect from the server on deactivation", ->
    [sock, ps] = setup()
    f = ->

    doAsync [
      (-> ps.onValue(f))
      sock.emitOpen
      (-> ps.offValue(f))
    ]

    expect(last(sock.sent)).to.become(Some(new Frame('DISCONNECT')))

  it "should end when connection to server is closed", ->
    [sock, ps] = setup()

    doAsync [
      sock.emitOpen
      sock.emitClose
    ]

    expect(head(ps)).to.become(None)

  it "should emit ERROR frames from the stomp server", ->
    [sock, ps] = setup()
    msg = 'Connection refused'
    err = new Frame('ERROR', R.createMapEntry('content-length', msg.length.toString()), msg)

    doAsync [
      sock.emitOpen
      emitFrame(sock, err)
      sock.emitClose
    ]

    expect(last(ps.errorsToValues())).to.become(Some(new FrameError(err)))

  it "should emit a PubSub object for interacting with STOMP when connected", ->
    [sock, ps] = setup()

    doAsync [
      sock.emitOpen
      emitConnected(sock)
      sock.emitClose
    ]

    expect(last(ps) .then R.invoke('getOrElse', {}))
      .to.eventually.have.ownProperty('subscribe').and.ownProperty('publish')

  describe "subscribe", ->
    it "should subscribe to the stomp topic using the headers given on activation", ->
      [sock, ps] = setup()
      dest = '/topic/wibble'
      subHdrs = {id: "3f2a17", persistent: "true"}
      sub = new Frame('SUBSCRIBE', R.assoc('destination', dest, subHdrs))
      wibbles = ps .flatMap R.invoke('subscribe', [subHdrs, dest])

      doAsync [
        (-> wibbles.onValue(->))
        sock.emitOpen
        emitConnected(sock)
        sock.emitClose
      ]

      expect(last(sock.sent)).to.become(Some(sub))

    it "should unsubscribe from the stomp topic on deactivation", ->
      [sock, ps] = setup()
      hdrs = {id: "1245"}
      unsub = new Frame('UNSUBSCRIBE', hdrs)
      wobbles = ps .flatMapLatest R.invoke('subscribe', [hdrs, '/topic/wobbles'])
      f = ->

      doAsync [
        (-> wobbles.onValue(f))
        sock.emitOpen
        emitConnected(sock)
        (-> wobbles.offValue(f))
      ]

      expect(last(sock.sent.take(3))).to.become(Some(unsub))

    it "should emit a Stomp.Frame for each message received for the subscription", ->
      [sock, ps] = setup()
      wibbles = ps .flatMapLatest R.invoke('subscribe', [{id: '1'}, '/topic/wibble'])

      hdrs = (sub, id) ->
        h = {subscription: sub, destination: '/topic/wibble'}
        h['content-type'] = 'text/plain'
        h['content-length'] = '1'
        h['message-id'] = id
        h

      wA = new Frame('MESSAGE', hdrs('1', '1'), "A")
      wB = new Frame('MESSAGE', hdrs('2', '2'), "B")
      wC = new Frame('MESSAGE', hdrs('1', '3'), "C")

      doAsync [
        sock.emitOpen
        emitConnected(sock)
        emitFrame(sock, wA)
        emitFrame(sock, wB)
        emitFrame(sock, wC)
        sock.emitClose
      ]

      expect(runLogValues(wibbles.map(R.omit(['ack', 'nack'])))).to.become([wA, wC])

  describe "publish", ->
    it "should publish message bodies to the topic, including the provided headers", ->
      [sock, ps] = setup()
      dest = '/topic/wibble/42'
      hdrs = {requestId: 'fa3c21', destination: dest}
      hdrs['content-length'] = '1'
      sends = ps .flatMap R.invoke('publish', [hdrs, dest])
      bodies = K.sequentially(100, ["A", "B", "C"])

      sA = new Frame('SEND', hdrs, "A")
      sB = new Frame('SEND', hdrs, "B")
      sC = new Frame('SEND', hdrs, "C")

      sends.combine(bodies, (f, a) -> f(a))
        .take(3)
        .onValue((t) -> t())
        .onEnd(sock.emitClose)

      doAsync [
        sock.emitOpen
        emitConnected(sock)
      ]

      expect(runLogValues(sock.sent.skip(1))).to.become([sA, sB, sC])

