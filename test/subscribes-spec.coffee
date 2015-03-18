R = require 'ramda'
{head, last, runLog, runLogValues} = require 'kefir-contrib-run'
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

nohbCfg = (ws) ->
  cfg(ws, 0, 0)

setup = ->
  sock = mkSocket()
  [sock, subscribes(nohbCfg(-> Right(sock.ws)))]

emitFrame = (sock, frame) -> () ->
  sock.emitMessage(frame.toString())

connected = ->
  hdrs = {version: '1.1'}
  hdrs['heart-beat'] = '0,0'
  new Frame('CONNECTED', hdrs)

emitConnected = (sock) ->
  emitFrame(sock, connected())

doAsync = (thunks) ->
  process.nextTick(->
    unless R.isEmpty(thunks)
      R.head(thunks)()
      doAsync(R.tail(thunks)))

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

    doAsync([
      (-> subs.onValue(->)),
      sock.emitOpen
    ])

    expect(head(sock.sent)).to.become(Some(new Frame('CONNECT', hdrs)))

  it "should gracefully disconnect from the server on deactivation", ->
    [sock, subs] = setup()
    f = ->

    doAsync([
      (-> subs.onValue(f)),
      sock.emitOpen,
      (-> subs.offValue(f))
    ])

    expect(last(sock.sent)).to.become(Some(new Frame('DISCONNECT')))

  it "should end when connection to server is closed", ->
    [sock, subs] = setup()

    doAsync([
      sock.emitOpen,
      sock.emitClose
    ])

    expect(head(subs)).to.become(None)

  it "should emit ERROR frames from the stomp server", ->
    [sock, subs] = setup()
    msg = 'Connection refused'
    err = new Frame('ERROR', R.createMapEntry('content-length', msg.length.toString()), msg)

    doAsync([
      sock.emitOpen,
      emitFrame(sock, err),
      sock.emitClose
    ])

    expect(last(subs.errorsToValues())).to.become(Some(new FrameError(err)))

  it "should emit a function for subscribing to STOMP topics when connected", ->
    [sock, subs] = setup()

    doAsync([
      sock.emitOpen,
      emitConnected(sock),
      sock.emitClose
    ])

    expect(last(subs)).to.be.fulfilled.and.eventually.have.property('x').that.is.an.instanceof(Function)

  describe "subscribed stream", ->
    it "should subscribe to the stomp topic using the headers given on activation", ->
      [sock, subs] = setup()
      dest = '/topic/wibble'
      subHdrs = {id: "3f2a17", persistent: "true"}
      sub = new Frame('SUBSCRIBE', R.assoc('destination', dest, subHdrs))
      wibbles = subs .flatMap R.flip(R.apply)([subHdrs, dest])

      doAsync([
        (-> wibbles.onValue(->)),
        sock.emitOpen,
        emitConnected(sock),
        sock.emitClose
      ])

      expect(last(sock.sent)).to.become(Some(sub))

    it "should unsubscribe from the stomp topic on deactivation", ->
      [sock, subs] = setup()
      hdrs = {id: "1245"}
      unsub = new Frame('UNSUBSCRIBE', hdrs)
      wobbles = subs .flatMapLatest R.flip(R.apply)([hdrs, '/topic/wobbles'])
      f = ->

      doAsync([
        (-> wobbles.onValue(f)),
        sock.emitOpen,
        emitConnected(sock),
        (-> wobbles.offValue(f))
      ])

      expect(last(sock.sent.take(3))).to.become(Some(unsub))

    it "should emit a Stomp.Frame for each message received for the subscription", ->
      [sock, subs] = setup()
      wibbles = subs .flatMapLatest R.flip(R.apply)([{id: '1'}, '/topic/wibble'])

      hdrs = (sub, id) ->
        h = {subscription: sub, destination: '/topic/wibble'}
        h['content-type'] = 'text/plain'
        h['content-length'] = '1'
        h['message-id'] = id
        h

      wA = new Frame('MESSAGE', hdrs('1', '1'), "A")
      wB = new Frame('MESSAGE', hdrs('2', '2'), "B")
      wC = new Frame('MESSAGE', hdrs('1', '3'), "C")

      doAsync([
        sock.emitOpen,
        emitConnected(sock),
        emitFrame(sock, wA),
        emitFrame(sock, wB),
        emitFrame(sock, wC),
        sock.emitClose
      ])

      expect(runLogValues(wibbles.map(R.omit(['ack', 'nack'])))).to.become([wA, wC])

