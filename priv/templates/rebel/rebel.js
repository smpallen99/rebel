(function(){
  console.log('loading rebel...')
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
    run: function(return_token, session_token, broadcast_topic) {
      console.debug('run', return_token, session_token)
      this.Socket = window.Socket

      this.return_token = return_token
      this.session_token = session_token
      this.self = this
      // this.myid = uuid()
      this.onload_launched = false
      this.already_connected = false
      this.channels = {}
      this.default_channel = '<%= default_channel %>'
      this.rebel_topic = broadcast_topic;

      var rebel = this

      // rebel.load.forEach((fx) => {
      //   fx(rebel)
      // })

      for (var i = 0; i < rebel.load.length; i++) {
        var fx = rebel.load[i];
        fx(rebel);
      }

      this.socket = new this.Socket("<%= Rebel.Config.get(:socket) %>",
        {params: Object.assign({__rebel_return: return_token},
          <%= conn_opts %>)})

      this.socket.onError(error => {
        const event = new Event('SocketError')
        document.querySelector('body').dispatchEvent(event)
      })

      this.socket.connect()

      this.return_channel = this.socket.channel("return:" + this.rebel_topic, {});

      this.return_channel.join().receive("error", function(resp) {
        console.warn("Unable to join the Rebel Channel", resp);
      }).receive("ok", function(resp) {
        rebel.return_channel.on("event", function(message) {
          if (messaage.finished && rebel.event_reply_table[message.finished]) {
            rebel.event_reply_table[message.finished]();
            delete rebel.event_reply_table[message.finished];
          }
        });
      });

      this.socket.onClose(function(event) {

        for (var di = 0; di < rebel.disconnected.length; di++) {
          var fxd = rebel.disconnected[di];
        // rebel.disconnected.forEach(function(fx) {
          fxd(rebel)
        }
      })
      this.channels = {}
    },
    run_channel: function(channel_name, session_token, broadcast_topic) {
      console.debug('run_channel', channel_name, broadcast_topic, session_token)
      let rebel = window.Rebel
      let channel = {topic: broadcast_topic}

      if (this.channels[channel_name] && this.channels[channel_name].channel) {
        console.debug('existing channel remove bindings', channel_name, broadcast_topic, session_token)
        this.channels[channel_name].channel.bindings = []
      }

      let chan = this.socket.channel(channel_name + ":" + broadcast_topic, <%= conn_opts %>)

      channel.rebel_session_token = session_token

      // launch all on_load functions
      rebel.load.forEach((fx) => {
        fx(channel_name, rebel)
      })

      chan.join()
        .receive("error", (resp) => {
          // TODO: communicate it to user
          console.error("Unable to join the Rebel Channel", channel_name, resp)
        })
        .receive("ok", (resp) => {
          console.debug('received ok for join on channel', channel_name)
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
      console.debug('run_hander', channel_name)
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
    disable_rebel_events: function() { },
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
  console.debug('about to run')

  Rebel.run('<%= controller_and_action %>', '<%= rebel_session_token %>', '<%= broadcast_topic %>')

  console.debug('about to run channels')

  <%= Enum.map channels, fn {channel_name, broadcast_topic, session_token} -> %>
    Rebel.run_channel('<%= channel_name %>', '<%= session_token %>', '<%= broadcast_topic %>')
  <% end %>
})();
