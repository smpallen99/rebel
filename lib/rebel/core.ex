defmodule Rebel.Core do
  @moduledoc ~S"""
  Drab Module with the basic communication from Server to the Browser. Does not require any libraries like jQuery,
  works on pure Phoenix.

      defmodule DrabPoc.JquerylessCommander do
        use Drab.Commander, modules: []

        def clicked(socket, payload) do
          socket |> console("You've sent me this: #{payload |> inspect}")
        end
      end

  See `Drab.Commander` for more info on Drab Modules.

  ## Events

  Events are defined directly in the HTML by adding `drab-event` and `drab-handler` properties:

      <button drab-event='click' drab-handler='button_clicked'>clickme</button>

  Clicking such button launches `DrabExample.PageCommander.button_clicked/2` on the Phoenix server.

  There are few shortcuts for the most popular events: `click`, `keyup`, `keydown`, `change`. For this event
  an attribute `drab-EVENT_NAME` must be set. The following like is an equivalent for the previous one:

      <button drab-click='button_clicked'>clickme</button>

  Normally Drab operates on the user interface of the browser which generared the event, but it is possible to broadcast
  the change to all the browsers which are currently viewing the same page. See the bang functions in `Drab.Query` module.

  ## Event handler functions

  The event handler function receives two parameters:
  * `socket` - the websocket used to communicate back to the page by `Drab.Query` functions
  * `sender` - a map contains information of the object which sent the event; keys are binary strings

  The `sender` map:

      %{
        "id"      => "sender object ID attribute",
        "name"    => "sender object 'name' attribute",
        "class"   => "sender object 'class' attribute",
        "text"    => "sender node 'text'",
        "html"    => "sender node 'html', result of running .html() on the node",
        "value"   => "sender object value",
        "data"    => "a map with sender object 'data-xxxx' attributes, where 'xxxx' are the keys",
        "event"   => "a map with choosen properties of `event` object"
        "drab_id" => "internal"
        "form"    => "a map of values of the sourrounding form"
      }

  Example:

      def button_clicked(socket, sender) do
        # using Drab.Query
        socket |> update(:text, set: "clicked", on: this(sender))
      end

  `sender` may contain more fields, depending on the used Drab module. Refer to module documentation for more.

  ### Form values

  If the sender object is inside a <form> tag, it sends the "form" map, which contains values of all the inputs
  found withing the form. Keys of that map are "name" attribute of the input or, if not found, an "id"
  attribute. If neither "name" or "id" is given, the value of the form is not included.

  ## Running Elixir code from the Browser

  There is the Javascript method `Drab.run_handler()` in global `Drab` object, which allows you to run the Elixir
  function defined in the Commander.

      Drab.run_handler(event_name, function_name, argument)

  Arguments:
  * event_name(string) - name of the even which runs the function
  * function_name(string) - function name in corresponding Commander module
  * argument(anything) - any argument you want to pass to the Commander function

  Returns:
  * no return, does not wait for any answer

  Example:

      <button onclick="Drab.run_handler('click', 'clicked', {click: 'clickety-click'});">
        Clickme
      </button>

  The code above runs function named `clicked` in the corresponding Commander, with
  the argument `%{"click" => "clickety-click}"`

  ## Store

  Analogically to Plug, Drab can store the values in its own session. To avoid confusion with the Plug Session session,
  it is called a Store. You can use functions: `put_store/3` and `get_store/2` to read and write the values
  in the Store. It works exactly the same way as a "normal", Phoenix session.

  * By default, Drab Store is kept in browser Local Storage. This means it is gone when you close the browser
    or the tab. You may set up where to keep the data with drab_store_storage config entry.
  * Drab Store is not the Plug Session! This is a different entity. Anyway, you have an access
    to the Plug Session (details below).
  * Drab Store is stored on the client side and it is signed, but - as the Plug Session cookie - not ciphered.

  ## Session

  Although Drab Store is a different entity than Plug Session (used in Controllers), there is a way
  to access the Session. First, you need to whitelist the keys you wan to access in `access_session/1` macro
  in the Commander (you may give it a list of atoms or a single atom). Whitelisting is due to security:
  it is kept in Token, on the client side, and it is signed but not encrypted.

      defmodule DrabPoc.PageCommander do
        use Drab.Commander

        onload :page_loaded,
        access_session :drab_test

        def page_loaded(socket) do
          socket
          |> update(:val, set: get_session(socket, :drab_test), on: "#show_session_test")
        end
      end

  There is not way to update session from Drab. Session is read-only.
  """
  require Logger

  # @behaviour Drab
  use Rebel.Module
  # def prerequisites(), do: []
  def js_templates(), do: ["rebel.core.js"]

  @doc """
  Helper for broadcasting functions, returns topic for a given URL path.

      iex> same_path("/test/live")
      "same_path:/test/live"
  """
  def same_path(url), do: "same_path:#{url}"

  @doc """
  Helper for broadcasting functions, returns topic for a given controller.

      iex> same_controller(DrabTestApp.LiveController)
      "controller:Elixir.DrabTestApp.LiveController"
  """
  def same_controller(controller), do: "controller:#{controller}"

  @doc """
  Helper for broadcasting functions, returns topic for a given topic string.
      iex> same_topic("mytopic")
      "topic:mytopic"
  """
  def same_topic(topic), do: "topic:#{topic}"

  @doc false
  def encode_js(value), do: Poison.encode!(value)

  @doc false
  def decode_js(value) do
    case Poison.decode(value) do
      {:ok, v} -> v
      _ -> value
    end
  end

  @doc """
  Finds the DOM object which triggered the event. To be used only in event handlers.

      def button_clicked(socket, sender) do
        set_prop socket, this(sender), innerText: "already clicked"
        set_prop socket, this(sender), disabled: true
      end

  Do not use it with with broadcast functions (`Drab.Query.update!`, `Drab.Core.broadcast_js`, etc),
  because it returns the *exact* DOM object in *exact* browser. In case if you want to broadcast, use
  `this!/1` instead.

  """
  def this(sender) do
    "[rebel-id=#{Rebel.Core.encode_js(sender["rebel_id"])}]"
  end

  @doc """
  Like `this/1`, but returns object ID, so it may be used with broadcasting functions.

      def button_clicked(socket, sender) do
        socket |> update!(:text, set: "alread clicked", on: this!(sender))
        socket |> update!(attr: "disabled", set: true, on: this!(sender))
      end

  Raises exception when being used on the object without an ID.
  """
  def this!(sender) do
    id = sender["id"]
    unless id, do: raise ArgumentError, """
    Try to use Rebel.Core.this!/1 on DOM object without an ID:
    #{inspect(sender)}
    """
    "##{id}"
  end
end
