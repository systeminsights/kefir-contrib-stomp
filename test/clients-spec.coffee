R = require 'ramda'
{head, last} = require 'kefir-contrib-run'
{Frame} = require 'stompjs'
{Some, None} = require 'fantasy-options'
{Left, Right} = require 'fantasy-eithers'
{clients, Transport, Config, StompError, FrameError} = require '../src/index'
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
  [sock, clients(nohbCfg(-> Right(sock.ws)))]

emitFrame = (sock, frame) -> () ->
  sock.emitMessage(frame.toString())

connected = ->
  hdrs = {version: '1.1'}
  hdrs['heart-beat'] = '0,0'
  new Frame('CONNECTED', hdrs)

emitConnected = (sock) ->
  emitFrame(sock, connected())

describe "clients", ->
  it "should emit Ws create error and end", ->
    err = new Error("Create failed")
    s = clients(nohbCfg(-> Left(err)))
    expect(head(s)).to.be.rejectedWith(StompError, /Create failed/)

  it "should connect to the server on activation", ->
    sock = mkSocket()
    hdrs = {host: 'foo.example.com', login: 'baz', passcode: 'quux'}
    hdrs = R.assoc('heart-beat', '5000,10000', hdrs)
    hdrs = R.assoc('accept-version', '1.1,1.0', hdrs)
    clis = clients(cfg((-> Right(sock.ws)), 5000, 10000))

    doAsync [
      (-> clis.onValue(->))
      sock.emitOpen
    ]

    expect(head(sock.sent)).to.become(Some(new Frame('CONNECT', hdrs)))

  it "should gracefully disconnect from the server on deactivation", ->
    [sock, clis] = setup()
    f = ->

    doAsync [
      (-> clis.onValue(f))
      sock.emitOpen
      (-> clis.offValue(f))
    ]

    expect(last(sock.sent)).to.become(Some(new Frame('DISCONNECT')))

  it "should end when connection to server is closed", ->
    [sock, clis] = setup()

    doAsync [
      sock.emitOpen
      sock.emitClose
    ]

    expect(head(clis)).to.become(None)

  it "should emit ERROR frames from the stomp server", ->
    [sock, clis] = setup()
    msg = 'Connection refused'
    err = new Frame('ERROR', R.createMapEntry('content-length', msg.length.toString()), msg)

    doAsync [
      sock.emitOpen
      emitFrame(sock, err)
      sock.emitClose
    ]

    expect(last(clis.errorsToValues())).to.become(Some(new FrameError(err)))

  it "should emit a Client object for interacting with STOMP when connected", ->
    [sock, clis] = setup()

    doAsync [
      sock.emitOpen
      emitConnected(sock)
      sock.emitClose
    ]

    expect(last(clis).then((o) -> o.getOrElse({})))
      .to.eventually.have
      .ownProperty('connected').and
      .ownProperty('publish').and
      .ownProperty('subscribe').and
      .ownProperty('unsubscribe')

