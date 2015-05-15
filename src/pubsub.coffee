# :: Kefir Error Boolean -> (Destination -> Headers -> Body -> ()) -> (Destination -> Headers -> (Stomp.Frame -> ()) -> SubId) -> (SubId -> ())
create = (connected, publish, subscribe, unsubscribe) ->
  {connected, publish, subscribe, unsubscribe}

module.exports = {
  create
}

