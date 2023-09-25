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

      {conn_opts, assigns} =
        [{:__controller, controller} | assigns]
        |> Keyword.pop(:conn_opts, [])

      # Logger.warning "{conn_opts, assigns} " <> inspect({conn_opts, assigns})
      controller_and_action =
        Phoenix.Token.sign(
          conn,
          "controller_and_action",
          __controller: controller,
          __action: Phoenix.Controller.action_name(conn),
          __assigns: assigns
        )

      templates = ~w(rebel.core.js rebel.element.js rebel.events.js)

      conn_opts =
        Enum.map(conn_opts, fn {k, v} ->
          "#{k}: #{v}"
        end)
        |> Enum.join(", ")

      bindings = [
        controller_and_action: controller_and_action,
        templates: templates,
        channels: process_channels(conn, rebel, controller),
        rebel_session_token: "",
        default_channel: rebel.default_channel,
        conn_opts: "{" <> conn_opts <> "}",
        broadcast_topic: "same_controller"
      ]

      js = render_template("rebel.js", bindings)

      Phoenix.HTML.raw("""
      <script>
        #{js}
      </script>
      """)
    else
      ""
    end
  end

  defp process_channels(conn, rebel, controller) do
    for channel <- rebel.channels, reduce: [] do
      acc ->
        ch_rebel = channel.__rebel__()

        with %{} = chan_rebel <- ch_rebel[controller],
            true <- should_join?(conn, chan_rebel) do
          session =
            for key <- ch_rebel.access_session,
                into: %{},
                do: {key, Plug.Conn.get_session(conn, key)}

          session_token = Rebel.Core.tokenize_store(conn, session)

          broadcast_topic = topic(conn, channel, chan_rebel.broadcasting, controller)
          [{chan_rebel.name, broadcast_topic, session_token} | acc]
        else
          _ -> acc
        end
    end
  end

  defp should_join?(conn, %{channel: channel}) do
    if function_exported?(channel, :should_join?, 1) do
      channel.should_join?(conn)
    else
      true
    end
  end

  defp topic(conn, channel, broadcasting, controller) do
    channel.topic(broadcasting, controller, conn.request_path, conn.assigns)
  end
end
