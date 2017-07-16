defmodule Rebel.Client do
  @moduledoc """
  Enable Drab on the browser side. Must be included in HTML template, for example
  in `web/templates/layout/app.html.eex`:

      <%= Drab.Client.js(@conn) %>

  after the line which loads app.js:

      <script src="<%= static_path(@conn, "/js/app.js") %>"></script>
  """

  import Rebel.Template
  require Logger

  @doc """
  Generates JS code which runs Drab. Passes controller and action name, tokenized for safety.
  Runs only when the controller which renders current action has been compiled
  with `use Drab.Controller`.

  Optional argument may be a list of parameters which will be added to assigns to the socket.
  Example of `layout/app.html.eex`:

      <%= Drab.Client.js(@conn) %>
      <%= Drab.Client.js(@conn, user_id: 4, any_other: "test") %>

  Please remember that your parameters are passed to the browser as Phoenix Token. Token is signed,
  but not ciphered. Do not put any secret data in it.

  On the browser side, there is a global object `Drab`, which you may use to create your own channels
  inside Drab Socket:

      ch = Drab.socket.channel("mychannel:whatever")
      ch.join()
  """
  def js(conn, assigns \\ []) do
    controller = Phoenix.Controller.controller_module(conn)
    # Enable Drab only if Controller compiles with `use Drab.Controller`
    # in this case controller contains function `__drab__/0`
    if Enum.member?(controller.__info__(:functions), {:__rebel__, 0}) do
      rebel = controller.__rebel__()

      controller_and_action =
        Phoenix.Token.sign(conn, "controller_and_action",
        [__controller: controller,
        __action: Phoenix.Controller.action_name(conn),
        __assigns: assigns])

      channels =
        for channel <- rebel.channels do
          chan_rebel = channel.__rebel__()
          broadcast_topic = topic(chan_rebel.broadcasting,
            controller, conn.request_path)
          {chan_rebel.name, broadcast_topic}
        end

      # modules = [Drab.Core | commander.__drab__().modules] # Drab.Core is included by default
      # templates = Enum.map(modules, fn x -> "#{Module.split(x) |> Enum.join(".") |> String.downcase()}.js" end)
      # templates = Rebel.Module.all_templates_for(commander.__drab__().modules)
      templates = ~w(rebel.core.js rebel.element.js rebel.events.js)

      # access_session = commander.__drab__().access_session
      # session = access_session
      #   |> Enum.map(fn x -> {x, Plug.Conn.get_session(conn, x)} end)
      #   |> Enum.into(%{})
      # # Logger.debug("**** #{inspect session}")

      # session_token = Drab.Core.tokenize_store(conn, session)
      # session_token = Drab.tokenize(conn, session)

      bindings = [
        controller_and_action: controller_and_action,
        templates: templates,
        channels: channels,
        rebel_session_token: "",
        default_channel: rebel.default_channel
        # drab_session_token: session_token,
      ]

      js = render_template("rebel.js", bindings)

      Phoenix.HTML.raw """
      <script>
        #{js}
      </script>
      """
    else
      ""
    end
  end

  # defp topic(:all, _, _), do: "all"
  defp topic(:same_path, _, path), do: Rebel.Core.same_path(path)
  defp topic(:same_controller, controller, _), do: Rebel.Core.same_controller(controller)
  defp topic(topic, _, _) when is_binary(topic), do: Rebel.Core.same_topic(topic)
end
