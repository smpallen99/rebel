console.log('rebel.core init')
Rebel.on_connect(function(resp, channel_name, rebel) {
  let channel = rebel.channels[channel_name].channel
  // prevent reassigning messages
  if (!rebel.already_connected) {
    channel.on("onload", function(message) {
      // reply from onload is not expected
    })

    // exec is synchronous, returns the result
    channel.on("execjs", function(message) {
      var output
      try {
        output = {
          ok: [
            message.sender,
            eval(message.js)]
        }
      } catch(e) {
        output = {
          error: [
            message.sender,
            e.message]
        }
      }
      channel.push("execjs", output)
    })

    // broadcast does not return a meesage
    channel.on("broadcastjs", function(message) {
      eval(message.js)
    })

    // console.log
    channel.on("console", function(message) {
      console.log(message.log)
    })
  }

  // launch server-side onconnect callback - every time it is connected
  channel.push("onconnect", {
    store_token: Rebel.store_token,
    payload: payload()
  })

  // initialize onload on server side, just once
  if (!rebel.onload_launched) {
    channel.push("onload", { store_token: Rebel.store_token })
    rebel.onload_launched = true
  }
})

