defmodule Rebel.Channel do
  defmacro __using__(options) do
    # opts = Map.merge(%Rebel.Channel.Config{}, Enum.into(options, %{}))
    # modules = Enum.map(opts.modules, fn x ->
    #   case x do
    #     # TODO: don't like this hack
    #     {:__aliases__, _, m} -> Module.concat(m)
    #     _ -> x
    #   end
    # end)
    # modules_to_import = LivePage.Module.all_modules_for(modules)

    quote do
      use Phoenix.Channel, Keyword.get(unquote(options), :channel_opts, [])

      import unquote(__MODULE__)
      import Rebel.Core
      import Rebel.Utils

      require Logger

      o = Enum.into(unquote(options) || [], %{channel: __MODULE__})

      intercepts = unquote(options)[:intercepts]

      controllers =
        case unquote(options)[:controllers] do
          nil ->
            [unquote(options)[:controller] || get_module(__MODULE__, "Channel", "Controller")]

          controllers ->
            controllers
        end

      # controller = unquote(options)[:controller] || get_module(__MODULE__, "Channel", "Controller")
      view = unquote(options)[:view] || get_module(__MODULE__, "Channel", "View")

      opts =
        for controller <- controllers, into: o do
          {controller,
           %Rebel.Channel.Config{controller: controller, view: view}
           |> Map.from_struct()
           |> Map.merge(o)}
        end

      @options Map.put(opts, :access_session, [])

      if intercepts do
        intercept(intercepts)
      end

      # unquote
      #   # opts = Map.merge(%Drab.Commander.Config{}, Enum.into(options, %{}))
      #   modules_to_import
      #   |> Enum.map(fn module ->
      #     quote do
      #       import unquote(module)
      #     end
      #   end)
      # end

      def name do
        @options[:name] || "__rebel"
      end

      # @doc """
      # A shorthand for `Phoenix.View.render_to_string/3`. Injects the corresponding view.
      # """
      # def render_to_string(template, assigns) do
      #   view = __MODULE__.__rebel__().view
      #   Phoenix.View.render_to_string(view, template, assigns)
      # end

      @doc """
      A shorthand for `Phoenix.View.render_to_string/3`.
      """
      def render_to_string(view, template, assigns) do
        Phoenix.View.render_to_string(view, template, assigns)
      end

      @before_compile unquote(__MODULE__)

      # def onload(socket, payload) do
      #   {:noreply, socket}
      # end

      # def onconnect(socket, payload) do
      #   {:noreply, socket}
      # end

      defp verify_and_cast(event_name, params, socket) do
        p = [event_name, socket] ++ params
        GenServer.cast(socket.assigns.__rebel_pid, List.to_tuple(p))
        {:noreply, socket}
      end

      defp sender(socket, sender_encrypted) do
        Rebel.detokenize(socket, sender_encrypted)
      end

      def topic(broadcasting, controller, request_path, conn_assigns)

      def topic(:same_path, _, path, _conn_assigns),
        do: Rebel.Core.same_path(path)

      def topic(:same_controller, controller, _, _),
        do: Rebel.Core.same_controller(controller)

      def topic(topic, _, _, _) when is_binary(topic),
        do: Rebel.Core.same_topic(topic)

      def join(event, payload, socket) do
        # Logger.warning "event: #{inspect event}"
        # Logger.warning "payload: #{inspect payload}"
        # Logger.warning "assigns: #{inspect socket.assigns}"
        [_ | broadcast_topic] = String.split(event, ":")
        # socket already contains controller and action
        socket_with_topic =
          socket
          |> assign(:__broadcast_topic, broadcast_topic)
          |> assign(:__channel_name, __MODULE__.name())
          |> Rebel.Core.set_store()

        {:ok, pid} = Rebel.start_link(socket_with_topic)

        # Logger.warning "+++++++++ Channel join self: #{inspect self()}, rebel_pid #{inspect pid}"

        socket_with_pid = assign(socket_with_topic, :__rebel_pid, pid)

        {:ok, socket_with_pid}
      end

      defoverridable join: 3, topic: 4

      def handle_info({:rebel_return_assigns, assigns}, socket) do
        {:noreply, struct(socket, assigns: assigns)}
      end

      def handle_in("onload", _, socket) do
        verify_and_cast(:onload, [], socket)
      end

      def handle_in("onconnect", payload, socket) do
        Rebel.set_socket(socket.assigns.__rebel_pid, socket)
        verify_and_cast(:onconnect, [payload["payload"]], socket)
      end

      def handle_in("execjs", %{"ok" => [sender_encrypted, reply]}, socket) do
        # sender contains PID of the process which sent the query
        # sender is waiting for the result
        # Logger.warning ".... sender_encrypted: #{inspect sender_encrypted}"
        # Logger.info ".... reply: #{inspect reply}"
        {sender, ref} = sender(socket, sender_encrypted)
        # Logger.info "{sender, ref}: #{inspect {sender, ref}}"
        send(
          sender,
          {:got_results_from_client, :ok, ref, reply}
        )

        {:noreply, socket}
      end

      def handle_in("modal", %{"ok" => [sender_encrypted, reply]}, socket) do
        # sender contains PID of the process which sent the query
        # sender is waiting for the result
        # Logger.warning ".... sender_encrypted: #{inspect sender_encrypted}"
        # Logger.info ".... reply: #{inspect reply}"
        {sender, ref} = sender(socket, sender_encrypted)
        # Logger.info "{sender, ref}: #{inspect {sender, ref}}"
        send(
          sender,
          {:got_results_from_client, :ok, ref, reply}
        )

        {:noreply, socket}
      end

      def handle_in("execjs", %{"error" => [sender_encrypted, reply]}, socket) do
        {sender, ref} = sender(socket, sender_encrypted)

        send(
          sender,
          {:got_results_from_client, :error, ref, reply}
        )

        {:noreply, socket}
      end

      def handle_in(
            "event",
            %{
              "event" => event_name,
              "payload" => payload,
              "event_handler_function" => event_handler_function,
              "reply_to" => reply_to
            },
            socket
          ) do
        # event name is currently not used (0.2.0)
        verify_and_cast(event_name, [payload, event_handler_function, reply_to], socket)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __rebel__() do
        @options
      end
    end
  end

  Enum.each([:onload, :onconnect, :ondisconnect], fn macro_name ->
    @doc """
    Sets up the callback for #{macro_name}. Receives handler function name as an atom.

        #{macro_name} :event_handler_function

    See `Drab.Commander` summary for details.
    """
    defmacro unquote(macro_name)(event_handler) when is_atom(event_handler) do
      m = unquote(macro_name)

      quote bind_quoted: [m: m], unquote: true do
        Map.get(@options, m) &&
          raise CompileError, description: "Only one `#{inspect(m)}` definition is allowed"

        @options Map.put(@options, m, unquote(event_handler))
      end
    end

    defmacro unquote(macro_name)(unknown_argument) do
      raise CompileError,
        description: """
        Only atom is allowed in `#{unquote(macro_name)}`. Given: #{inspect(unknown_argument)}
        """
    end
  end)

  def check_handler_existence!(channel_module, handler) do
    unless function_exported?(channel_module, handler, 2) do
      raise "Rebel can't find the handler: \"#{channel_module}.#{handler}/2\"."
    end
  end

  @doc """
  Rebel may allow an access to specified Plug Session values. For this,
  you must whitelist the keys of the session map. Only this keys will
  be available to `Rebel.Core.get_session/2`

      defmodule MyApp.MyChannel do
        user Rebel.Channel

        access_session [:user_id, :counter]
      end

  Keys are whitelisted due to security reasons. Session token is stored on
  the client-side and it is signed, but not encrypted.
  """
  defmacro access_session(session_keys) when is_list(session_keys) do
    quote do
      access_sessions = Map.get(@options, :access_session)
      @options Map.put(@options, :access_session, access_sessions ++ unquote(session_keys))
    end
  end

  defmacro access_session(session_key) when is_atom(session_key) do
    quote do
      access_sessions = Map.get(@options, :access_session)
      @options Map.put(@options, :access_session, [unquote(session_key) | access_sessions])
    end
  end

  defmacro access_session(unknown_argument) do
    raise CompileError,
      description: """
      Only atom or list are allowed in `access_session`. Given: #{inspect(unknown_argument)}
      """
  end
end
