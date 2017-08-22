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
      console.log('execjs', message.js)
      try {
        output = {
          ok: [
            message.sender,
            eval(message.js)]
        }
      } catch(e) {
        console.error('execjs exception', e)
        output = {
          error: [
            message.sender,
            e.message]
        }
      }
      rebel.return_channel.push("execjs", output)
      // channel.push("execjs", output)
    })

    channel.on("modal", function(message) {
      window.rebel_modal = message
      eval(message.js)
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

  console.log('checking !onload_launched', !rebel.onload_launched)
  // initialize onload on server side, just once
  if (!rebel.onload_launched) {
    channel.push("onload", { store_token: Rebel.store_token })
    rebel.onload_launched = true
  }
})


