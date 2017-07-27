(function(){
  function uuid() {
    // borrowed from http://stackoverflow.com/questions/105034/create-guid-uuid-in-javascript
    var d = new Date().getTime();
    var uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      var r = (d + Math.random()*16)%16 | 0
      d = Math.floor(d/16)
      return (c=='x' ? r : (r&0x3|0x8)).toString(16)
    })
    return uuid
  }

  function closest(el, fn) {
    return el && (fn(el) ? el : closest(el.parentNode, fn))
  }

  window.Rebel = {
    run: function(return_token, session_token) {
      console.log('run', return_token, session_token)
      this.Socket = require("phoenix").Socket

      this.return_token = return_token
      this.session_token = session_token
      this.self = this
      // this.myid = uuid()
      this.onload_launched = false
      this.already_connected = false
      this.channels = {}
      this.default_channel = '<%= default_channel %>'

      var rebel = this

      rebel.load.forEach((fx) => {
        fx(rebel)
      })

      this.socket = new this.Socket("<%= Rebel.Config.get(:socket) %>",
        {params: Object.assign({__rebel_return: return_token},
          <%= conn_opts %>)})

      this.socket.connect()

      this.socket.onClose(function(event) {
        rebel.disconnected.forEach(function(fx) {
          fx(rebel)
        })
      })
      this.channels = {}
    },
    run_channel: function(channel_name, session_token, broadcast_topic) {
      console.log('run_channel', channel_name, broadcast_topic)
      let rebel = window.Rebel
      let channel = {topic: broadcast_topic}
      let chan = this.socket.channel(channel_name + ":" + broadcast_topic, <%= conn_opts %>)

      chan.rebel_session_token = session_token

      // launch all on_load functions
      rebel.load.forEach((fx) => {
        fx(channel_name, rebel)
      })

      chan.join()
        .receive("error", (resp) => {
          // TODO: communicate it to user
          console.log("Unable to join the Rebel Channel", channel_name, resp)
        })
        .receive("ok", (resp) => {
          rebel.connected.forEach((fx) => {
            fx(resp, channel_name, rebel)
          })
          channel.already_connected = true
          // event is sent after Rebel finish processing the event
          chan.on("event", (message) => {
            // console.log("EVENT: ", message)
            if(message.finished && rebel.event_reply_table[message.finished]) {
              rebel.event_reply_table[message.finished]()
              delete rebel.event_reply_table[message.finished]
            }
          })
        })
      channel.channel = chan
      this.channels[channel_name] = channel
    },
    run_handler(channel_name, event_name, event_handler, payload, execute_after) {
      console.log('run_hander', channel_name)
      var reply_to = uuid()
      if(execute_after) {
        Rebel.event_reply_table[reply_to] = execute_after
      }
      var message = {
        event: event_name,
        event_handler_function: event_handler,
        payload: payload,
        reply_to: reply_to
      }
      this.channels[channel_name].channel.push("event", message)
    },
    load: [],
    connected: [],
    disconnected: [],
    additional_payloads: [],
    event_reply_table: {},
    on_connect: function(f) {
      this.connected.push(f)
    },
    on_disconnect: function(f) {
      this.disconnected.push(f)
    },
    on_load: function(f) {
      this.load.push(f)
    },
    set_rebel_store_token: (token) => {
      <%= Rebel.Template.render_template("rebel.store.#{Rebel.Config.get(:rebel_store_storage) |> Atom.to_string}.set.js", []) %>
    },
    get_rebel_store_token: () => {
      <%= Rebel.Template.render_template("rebel.store.#{Rebel.Config.get(:rebel_store_storage) |> Atom.to_string}.get.js", []) %>
    },
    get_rebel_session_token: function(channel) {
      return this.channels[channel].rebel_session_token
    }
  }

  <%=
    Enum.map(templates, fn template ->
      Rebel.Template.render_template(template, [])
    end)
  %>
  console.log('about to run')

  Rebel.run('<%= controller_and_action %>', '<%= rebel_session_token %>')

  console.log('about to run channels')

  <%= Enum.map channels, fn {channel_name, broadcast_topic, session_token} -> %>
    Rebel.run_channel('<%= channel_name %>', '<%= session_token %>', '<%= broadcast_topic %>')
  <% end %>
})();
