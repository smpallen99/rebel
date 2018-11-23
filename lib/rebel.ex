defmodule Rebel do
  @moduledoc """
  Documentation for Rebel.
  """
  use GenServer

  require Logger

  # @type t :: %Rebel{store: map, session: map, commander: atom, socket: Phoenix.Socket.t, priv: map}

  defstruct store: %{},
            session: %{},
            assigns: %{},
            channel: nil,
            controller: nil,
            socket: nil,
            priv: %{}

  ###############
  # Public API

  @doc false
  def start_link(socket) do
    Logger.debug("Rebel.start_link socket: #{inspect(socket)}")

    GenServer.start_link(
      __MODULE__,
      %__MODULE__{
        channel: get_channel(socket),
        controller: get_controller(socket),
        assigns: socket.assigns
      }
    )
  end

  def cast_fun(socket, fun) do
    GenServer.cast(socket.assigns.__rebel_pid, {:handle_fun, socket, fun})
  end

  def push_async(socket, pid, message, payload \\ [], _options \\ []) do
    ref = make_ref()
    push(socket, pid, ref, message, payload)
    socket
  end

  @doc false
  def push_and_wait_for_response(socket, pid, message, payload \\ [], options \\ []) do
    ref = make_ref()
    push(socket, pid, ref, message, payload)
    timeout = options[:timeout] || Rebel.Config.get(:browser_response_timeout)

    receive do
      {:got_results_from_client, status, ^ref, reply} ->
        {status, reply}
    after
      timeout ->
        # TODO: message is still in a queue
        {:error, "timed out after #{timeout} ms."}
    end
  end

  @doc false
  def push_and_wait_forever(socket, pid, message, payload \\ []) do
    push(socket, pid, nil, message, payload)

    receive do
      {:got_results_from_client, status, _, reply} ->
        {status, reply}
    end
  end

  # setter and getter functions
  Enum.each([:store, :session, :socket, :priv], fn name ->
    get_name = "get_#{name}" |> String.to_atom()
    update_name = "set_#{name}" |> String.to_atom()

    @doc false
    def unquote(get_name)(pid) do
      GenServer.call(pid, unquote(get_name))
    end

    @doc false
    def unquote(update_name)(pid, new_value) do
      GenServer.cast(pid, {unquote(update_name), new_value})
    end
  end)

  def get_assigns(socket) do
    GenServer.call(pid(socket), :get_assigns)
  end

  def put_assigns(socket, value) do
    GenServer.cast(pid(socket), {:put_assigns, value})
  end

  def get_assigns(socket, key, default \\ nil) do
    GenServer.call(pid(socket), {:get_assigns, key, default})
  end

  def put_assigns(socket, key, value) do
    GenServer.cast(pid(socket), {:put_assigns, key, value})
  end

  @doc false
  def push(socket, pid, ref, message, payload \\ []) do
    do_push_or_broadcast(socket, pid, ref, message, payload, &Phoenix.Channel.push/3)
  end

  @doc false
  def broadcast(subject, pid, message, payload \\ [])

  def broadcast(%Phoenix.Socket{} = socket, pid, message, payload) do
    do_push_or_broadcast(socket, pid, nil, message, payload, &Phoenix.Channel.broadcast/3)
  end

  def broadcast(subject, _pid, message, payload) when is_binary(subject) do
    Phoenix.Channel.Server.broadcast(
      Rebel.Config.pubsub(),
      "__rebel:#{subject}",
      message,
      Map.new(payload)
    )
  end

  def broadcast(topics, _pid, _ref, message, payload) when is_list(topics) do
    for topic <- topics do
      broadcast(topic, nil, message, payload)
    end

    :ok
  end

  @doc false
  def tokenize(socket, what, salt \\ "rebel token") do
    Phoenix.Token.sign(socket, salt, what)
  end

  @doc false
  def detokenize(socket, token, salt \\ "rebel token") do
    max_age = Application.get_env(:rebel, :token_max_age, 86400)

    case Phoenix.Token.verify(socket, salt, token, max_age: max_age) do
      {:ok, detokenized} ->
        detokenized

      {:error, reason} ->
        # let it die
        raise "Can't verify the token `#{salt}`: #{inspect(reason)}"
    end
  end

  # returns the commander name for the given controller (assigned in socket)
  @doc false
  def get_channel(socket) do
    socket.channel
    # controller = socket.assigns.__controller
    # controller.__rebel__()[:channel]
  end

  # returns the controller name used with the socket
  @doc false
  def get_controller(socket) do
    socket.assigns.__controller
  end

  # returns the view name used with the socket
  @doc false
  def get_view(socket) do
    controller = socket.assigns.__controller
    controller.__rebel__()[:view]
  end

  # returns the rebel_pid from socket
  @doc "Extract Rebel PID from the socket"
  def pid(socket) do
    socket.assigns.__rebel_pid
  end

  ####################
  # Callbacks

  def init(state) do
    # Logger.warn "Rebel.init state: #{inspect state}"
    # Logger.warn "+++++ Rebel pid: #{inspect self()}"
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  @doc false
  def handle_info({:EXIT, pid, :normal}, state) when pid != self() do
    # ignore exits of the subprocesses
    # Logger.debug "************** #{inspect pid} process exit normal"
    {:noreply, state}
  end

  @doc false
  def handle_info({:EXIT, pid, :killed}, state) when pid != self() do
    failed(state.socket, %RuntimeError{message: "Rebel Process #{inspect(pid)} has been killed."})
    {:noreply, state}
  end

  @doc false
  def handle_info({:EXIT, pid, {reason, stack}}, state) when pid != self() do
    # subprocess died
    Logger.error("""
    Rebel Process #{inspect(pid)} died because of #{inspect(reason)}
    #{Exception.format_stacktrace(stack)}
    """)

    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.error("""
    Rebel.handle_info unexpected message: #{inspect(message)}
    state was: #{inspect(state)}
    """)

    {:noreply, state}
  end

  @doc false
  def handle_cast({:onconnect, socket, payload}, %Rebel{channel: channel} = state) do
    # TODO: there is an issue when the below failed and client tried to reconnect again and again
    # tasks = [Task.async(fn -> Drab.Core.save_session(socket, Drab.Core.session(socket)) end),
    #          Task.async(fn -> Drab.Core.save_store(socket, Drab.Core.store(socket)) end)]
    # Enum.each(tasks, fn(task) -> Task.await(task) end)
    # Logger.error "received conconnect"

    # Logger.debug "******"
    # Logger.debug inspect(Drab.Core.session(socket))

    # IO.inspect payload

    socket = transform_socket(payload, socket, state)

    Rebel.Core.save_session(socket, Rebel.Core.session(socket))
    Rebel.Core.save_store(socket, Rebel.Core.store(socket))
    Rebel.Core.save_socket(socket)

    handle_callback(socket, channel, channel.__rebel__()[:onconnect])

    {:noreply, state}
  end

  @doc false
  def handle_cast({:onload, socket}, %{channel: channel} = state) do
    # {_, socket} = transform_payload_and_socket(payload, socket, commander_module)
    # IO.inspect state
    # Logger.error "received onload"

    handle_callback(socket, channel, channel.__rebel__()[:onload])
    {:noreply, state}
  end

  # casts for update values from the state
  Enum.each([:assigns, :store, :session, :socket, :priv], fn name ->
    msg_name = "set_#{name}" |> String.to_atom()
    @doc false
    def handle_cast({unquote(msg_name), value}, state) do
      new_state = Map.put(state, unquote(name), value)
      {:noreply, new_state}
    end
  end)

  def handle_cast({:put_assigns, value}, state) do
    {:noreply, struct(state, assigns: value)}
  end

  def handle_cast({:put_assigns, key, value}, state) do
    {:noreply, struct(state, assigns: Map.put(state.assigns, key, value))}
  end

  def handle_cast({:handle_fun, socket, fun}, state) do
    handle_fun(socket, fun, state)
  end

  @doc false
  # any other cast is an event handler
  def handle_cast({event_name, socket, payload, event_handler_function, reply_to}, state) do
    handle_event(socket, event_name, event_handler_function, payload, reply_to, state)
  end

  # calls for get values from the state
  Enum.each([:store, :session, :socket, :priv], fn name ->
    msg_name = "get_#{name}" |> String.to_atom()
    @doc false
    def handle_call(unquote(msg_name), _from, state) do
      value = Map.get(state, unquote(name))
      {:reply, value, state}
    end
  end)

  def handle_call(:get_assigns, _, state) do
    {:reply, state.assigns, state}
  end

  def handle_call({:get_assigns, key, default}, _, state) do
    {:reply, Map.get(state.assigns, key, default), state}
  end

  def terminate(_reason, %Rebel{store: store, session: session, channel: channel} = state) do
    if channel.__rebel__()[state.controller].ondisconnect do
      :ok =
        apply(channel, channel_config(channel, state.controller).ondisconnect, [store, session])
    end

    {:noreply, state}
  end

  ###############
  # Private

  defp handle_callback(socket, channel, callback) do
    if callback do
      # TODO: rethink the subprocess strategies - now it is just spawn_link
      spawn_link(fn ->
        try do
          apply(channel, callback, [socket])
        rescue
          e ->
            failed(socket, e)
        end
      end)
    end

    socket
  end

  defp transform_payload(payload, state) do
    # Logger.info "payload: #{inspect payload}"
    # Logger.info "state: #{inspect state}"

    all_modules =
      Rebel.Module.all_modules_for(state.channel.__rebel__()[state.controller].modules)

    # transform payload via callbacks in Rebel.Module
    Enum.reduce(all_modules, payload, fn m, p ->
      m.transform_payload(p, state)
    end)
  end

  defp transform_socket(payload, socket, state) do
    all_modules =
      Rebel.Module.all_modules_for(state.channel.__rebel__()[state.controller].modules)

    # transform socket via callbacks
    Enum.reduce(all_modules, socket, fn m, s ->
      m.transform_socket(s, payload, state)
    end)
  end

  defp handle_fun(socket, fun, state) do
    spawn_link(fn ->
      try do
        fun.()
      rescue
        e ->
          failed(socket, e)
      end
    end)

    {:noreply, state}
  end

  defp handle_event(
         socket,
         _event_name,
         event_handler_function,
         payload,
         reply_to,
         %Rebel{channel: channel_module} = state
       ) do
    # TODO: rethink the subprocess strategies - now it is just spawn_link
    spawn_link(fn ->
      try do
        check_handler_existence!(channel_module, event_handler_function)

        event_handler = String.to_existing_atom(event_handler_function)
        payload = Map.delete(payload, "event_handler_function")

        controller = socket.assigns.__controller

        payload = transform_payload(payload, state)
        socket = transform_socket(payload, socket, state)

        channel_cfg = channel_config(channel_module, controller)

        # run before_handlers first
        returns_from_befores =
          Enum.map(
            callbacks_for(event_handler, channel_cfg.before_handler),
            fn callback_handler ->
              apply(channel_module, callback_handler, [socket, payload])
            end
          )

        # if ANY of them fail (return false or nil), do not proceed
        unless Enum.any?(returns_from_befores, &(!&1)) do
          # run actuall event handler
          returned_from_handler = apply(channel_module, event_handler, [socket, payload])

          Enum.map(
            callbacks_for(event_handler, channel_cfg.after_handler),
            fn callback_handler ->
              apply(channel_module, callback_handler, [socket, payload, returned_from_handler])
            end
          )
        end
      rescue
        e ->
          failed(socket, e)
      after
        # push reply to the browser, to re-enable controls
        push_reply(socket, reply_to, channel_module, event_handler_function)
      end
    end)

    {:noreply, state}
  end

  defp check_handler_existence!(channel_module, handler) do
    unless function_exported?(channel_module, String.to_existing_atom(handler), 2) do
      raise "Rebel can't find the handler: \"#{channel_module}.#{handler}/2\"."
    end
  end

  defp failed(socket, e) do
    error = """
    Rebel Handler failed with the following exception:
    #{inspect(e)}
    #{Exception.format_stacktrace(System.stacktrace())}
    """

    Logger.error(error)

    if socket do
      js =
        Rebel.Template.render_template(
          "rebel.handler_error.#{Atom.to_string(env())}.js",
          message: Rebel.Core.encode_js(error)
        )

      {:ok, _} = Rebel.Core.exec_js(socket, js)
    end
  end

  defp push_reply(socket, reply_to, _, _) do
    Phoenix.Channel.push(socket, "event", %{
      finished: reply_to
    })
  end

  @doc false
  # Returns the list of callbacks (before_handler, after_handler) defined in handler_config
  def callbacks_for(_, []) do
    []
  end

  @doc false
  def callbacks_for(event_handler_function, handler_config) do
    # :uppercase, [{:run_before_each, []}, {:run_before_uppercase, [only: [:uppercase]]}]
    Enum.map(handler_config, fn {callback_name, callback_filter} ->
      case callback_filter do
        [] ->
          callback_name

        [only: handlers] ->
          if event_handler_function in handlers, do: callback_name, else: false

        [except: handlers] ->
          if event_handler_function in handlers, do: false, else: callback_name

        _ ->
          false
      end
    end)
    |> Enum.filter(& &1)
  end

  defp do_push_or_broadcast(socket, pid, ref, message, payload, function) do
    token = tokenize(socket, {pid, ref})
    # Logger.warn "{pid,ref} token " <> inspect({pid, ref}) <> " : " <> inspect(token)
    # Logger.warn "message: #{inspect message}"
    # Logger.warn "payload: #{inspect payload}"
    m = payload |> Enum.into(%{}) |> Map.merge(%{sender: token})
    function.(socket, message, m)
  end

  # if module is commander or controller with rebel enabled, it has __rebel/0
  # function with Rebel configuration
  defp channel_config(module, controller) do
    module.__rebel__()[controller]
  end

  @env Mix.env()
  def env, do: @env
end
