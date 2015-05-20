R = require 'ramda'
K = require 'kefir'
{head, last, runLog, runLogValues} = require 'kefir-contrib-run'
{Frame} = require 'stompjs'
{Some, None} = require 'fantasy-options'
{Left, Right} = require 'fantasy-eithers'
{frames, StompError, FrameError} = require '../src/index'
doAsync = require './do-async'

testClient = (isConnected) ->
  s = K.emitter()
  c = K.emitter()
  u = K.emitter()

  subId = 0
  handlers = {}

  connected: c.toProperty(isConnected)

  publish: (dest, hdrs, body) ->
    handlers[dest]?.call(null, new Frame('MESSAGE', hdrs, body))

  subscribe: (dest, hdrs, onMsg) ->
    handlers[dest] = onMsg
    doAsync([(-> s.emit([dest, hdrs]))]); ++subId

  unsubscribe: (id) ->
    doAsync([(-> u.emit(id))])

  setConnected: (v) ->
    c.emit(v)

  lastSubId: -> subId
  nextSubId: -> subId + 1
  unsubs: u
  subs: s


describe "frames", ->
  it "should subscribe to the stomp topic using the headers given on activation", ->
    client = testClient(true)
    dest = '/topic/wibble'
    subHdrs = {id: "3f2a17", persistent: "true"}
    wibbles = frames(client, subHdrs, dest)

    process.nextTick(-> wibbles.onValue(->))

    expect(head(client.subs)).to.become(Some([dest, subHdrs]))

  it "should unsubscribe from the stomp topic on deactivation", ->
    client = testClient(true)
    nextId = client.nextSubId()
    hdrs = {id: "1245"}
    wobbles = frames(client, hdrs, '/topic/wobbles')
    f = ->

    doAsync [
      (-> wobbles.onValue(f))
      (-> wobbles.offValue(f))
    ]

    expect(head(client.unsubs)).to.become(Some(nextId))

  it "should emit a Stomp.Frame for each message received for the subscription", ->
    client = testClient(true)
    dest = '/topic/wibble'
    wibbles = frames(client, {id: '1'}, dest)

    hdrs = (id) ->
      h = {destination: dest}
      h['content-type'] = 'text/plain'
      h['content-length'] = '1'
      h['message-id'] = id
      h

    wA = new Frame('MESSAGE', hdrs('1'), "A")
    wB = new Frame('MESSAGE', hdrs('2'), "B")
    wC = new Frame('MESSAGE', hdrs('3'), "C")

    doAsync [
      (-> client.publish(dest, hdrs('1'), "A"))
      (-> client.publish(dest, hdrs('2'), "B"))
      (-> client.publish(dest, hdrs('3'), "C"))
      (-> client.setConnected(false))
    ]

    expect(runLogValues(wibbles.map(R.omit(['ack', 'nack'])))).to.become([wA, wB, wC])

  it "should catch errors thrown by client.subscribe", ->
    testErr = new Error("FOR TESTING")
    client = {connected: K.constant(true), subscribe: -> throw testErr}
    wibbles = frames(client, {}, '/topic/wibble')

    expect(runLog(wibbles.mapErrors(R.prop('cause')))).to.become([Left(Some(testErr))])

  it "should end when client becomes disconnected", ->
    client = testClient(true)
    dest = '/topic/wibble'
    wibbles = frames(client, {id: '1'}, dest)

    wA = new Frame('MESSAGE', {}, "A")
    wB = new Frame('MESSAGE', {}, "B")
    wC = new Frame('MESSAGE', {}, "C")

    doAsync [
      (-> client.publish(dest, {}, "A"))
      (-> client.publish(dest, {}, "B"))
      (-> client.setConnected(false))
      (-> client.publish(dest, {}, "C"))
    ]

    expect(runLogValues(wibbles.map(R.omit(['ack', 'nack'])))).to.become([wA, wB])

  it "should never emit when client starts out disconnected", ->
    client = testClient(false)
    dest = '/topic/wibble'
    wibbles = frames(client, {id: '1'}, dest)

    wA = new Frame('MESSAGE', {}, "A")
    wB = new Frame('MESSAGE', {}, "B")
    wC = new Frame('MESSAGE', {}, "C")

    doAsync [
      (-> client.publish(dest, {}, "A"))
      (-> client.publish(dest, {}, "B"))
      (-> client.publish(dest, {}, "C"))
    ]

    expect(runLogValues(wibbles.map(R.omit(['ack', 'nack'])))).to.become([])

