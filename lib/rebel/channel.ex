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
      use Phoenix.Channel

      import unquote(__MODULE__)
      import Rebel.Core
      import Rebel.Utils

      require Logger

      o = Enum.into(unquote(options) || [], %{channel: __MODULE__})

      controller = unquote(options)[:controller] || get_module(__MODULE__, "Channel", "Controller")
      view = unquote(options)[:view] || get_module(__MODULE__, "Channel", "View")

      channel_config =
        Map.from_struct %Rebel.Channel.Config{controller: controller, view: view}

      @options Map.merge(channel_config, o)

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

      @doc """
      A shordhand for `Phoenix.View.render_to_string/3. Injects the corresponding view.
      """
      def render_to_string(template, assigns) do
        view = __MODULE__.__rebel__().view
        Phoenix.View.render_to_string(view, template, assigns)
      end

      @doc """
      A shordhand for `Phoenix.View.render_to_string/3.
      """
      def render_to_string(view, template, assigns) do
        Phoenix.View.render_to_string(view, template, assigns)
      end

      @before_compile unquote(__MODULE__)

      def onload(socket, payload) do
        Logger.info "onload payload: #{inspect payload}"
        {:noreply, socket}
      end

      def onconnect(socket, payload) do
        Logger.info "onconnect payload: #{inspect payload}"
        {:noreply, socket}
      end

      # defp verify_and_cast(event_name, params, socket) do
      #   p = [event_name, socket] ++ params
      #   GenServer.cast(socket.assigns.__drab_pid, List.to_tuple(p))
      #   {:noreply, socket}
      # end

      defp verify_and_cast(event_name, [payload, event_handler_function, reply_to], socket) do
        spawn_link fn ->
          event_handler = String.to_existing_atom(event_handler_function)
          try do
            check_handler_existence! __MODULE__, event_handler
            payload = Map.delete payload, "event_handler_function"
            apply __MODULE__, event_handler, [socket, payload]
          rescue e ->
            Logger.error "Event handler #{inspect __MODULE__}, #{inspect event_handler} failed. Error #{inspect e}"

          end
        end
        {:noreply, socket}
      end

      defp sender(socket, sender_encrypted) do
        Rebel.detokenize(socket, sender_encrypted)
      end

      def join(event, _, socket) do
        [_ | broadcast_topic] = String.split event, ":"
        # socket already contains controller and action
        socket_with_topic =
          socket
          |> assign(:__broadcast_topic, broadcast_topic)
          |> assign(:__channel_name, __MODULE__.name())

        # {:ok, pid} = Drab.start_link(socket)

        # socket_with_pid = assign(socket_with_topic, :__drab_pid, pid)

        {:ok, socket_with_topic}
      end

      defoverridable [onload: 2, onconnect: 2, join: 3]

      defp verify_and_cast(:onconnect, [payload], socket) do
        Logger.info ":onconnect payload: #{inspect payload}"
        {:noreply, socket}
      end

      def handle_in("onload", payload, socket) do
        onload socket, payload
      end

      def handle_in("onconnect", payload, socket) do
        onconnect socket, payload
      end

      def handle_in("execjs", %{"ok" => [sender_encrypted, reply]}, socket) do
        # sender contains PID of the process which sent the query
        # sender is waiting for the result
        {sender, ref} = sender(socket, sender_encrypted)
        send(sender,
          { :got_results_from_client, :ok, ref, reply })

        {:noreply, socket}
      end

      def handle_in("execjs", %{"error" => [sender_encrypted, reply]}, socket) do
        {sender, ref} = sender(socket, sender_encrypted)
        send(sender,
          { :got_results_from_client, :error, ref, reply })

        {:noreply, socket}
      end

      def handle_in("event", %{
          "event" => event_name,
          "payload" => payload,
          "event_handler_function" => event_handler_function,
          "reply_to" => reply_to
          }, socket) do
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

  def check_handler_existence!(channel_module, handler) do
    unless function_exported?(channel_module, handler, 2) do
      raise "Regent can't find the handler: \"#{channel_module}.#{handler}/2\"."
    end
  end
  # def handle_in("execjs", %{"ok" => [sender_encrypted, reply]}, socket) do
  #   # sender contains PID of the process which sent the query
  #   # sender is waiting for the result
  #   {sender, ref} = sender(socket, sender_encrypted)
  #   send(sender,
  #     { :got_results_from_client, :ok, ref, reply })

  #   {:noreply, socket}
  # end

  # def handle_in("execjs", %{"error" => [sender_encrypted, reply]}, socket) do
  #   {sender, ref} = sender(socket, sender_encrypted)
  #   send(sender,
  #     { :got_results_from_client, :error, ref, reply })

  #   {:noreply, socket}
  # end

  # def handle_in("modal", %{"ok" => [sender_encrypted, reply]}, socket) do
  #   # sends { "button_name", %{"Param" => "value"}}
  #   {sender, ref} = sender(socket, sender_encrypted)
  #   send(sender,
  #     {
  #       :got_results_from_client,
  #       :ok,
  #       ref,
  #       {
  #         reply["button_clicked"] |> String.to_existing_atom,
  #         reply["params"] |> Map.delete("__drab_modal_hidden_input")
  #       }
  #     })

  #   {:noreply, socket}
  # end

  # def handle_in("waiter", %{"drab_waiter_token" => waiter_token, "sender" => sender}, socket) do
  #   {pid, ref} = Drab.Waiter.detokenize_waiter(socket, waiter_token)

  #   send(pid, {:waiter, ref, sender})

  #   {:noreply, socket}
  # end

end
