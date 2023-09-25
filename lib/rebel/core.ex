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

  def async_js(socket, js, options \\ []) do
    Rebel.push_async(socket, self(), "broadcastjs", [js: js], options)
  end

  @doc """
  Synchronously executes the given javascript on the client side.

  Returns tuple `{status, return_value}`, where status could be `:ok` or `:error`, and return value
  contains the output computed by the Javascript or the error message.

  ### Options

  * `timeout` in milliseconds

  ### Examples

      iex> socket |> exec_js("2 + 2")
      {:ok, 4}

      iex> socket |> exec_js("not_existing_function()")
      {:error, "not_existing_function is not defined"}

      iex> socket |> exec_js("for(i=0; i<1000000000; i++) {}")
      {:error, "timed out after 5000 ms."}

      iex> socket |> exec_js("alert('hello from IEx!')", timeout: 500)
      {:error, "timed out after 500 ms."}

  """
  def exec_js(socket, js, options \\ []) do
    timeout = options[:timeout] || Rebel.Config.get(:browser_response_timeout)
    reply_pid = self()

    spawn(fn ->
      response = Rebel.push_and_wait_for_response(socket, self(), "execjs", [js: js], options)
      send(reply_pid, {:reply, response})
    end)

    receive do
      {:reply, response} ->
        response
    after
      timeout ->
        {:error, "timed out after #{timeout} ms."}
    end
  end

  @doc """
  Exception raising version of `exec_js/2`

  ### Examples

        iex> socket |> exec_js!("2 + 2")
        4

        iex> socket |> exec_js!("nonexistent")
        ** (Rebel.JSExecutionError) nonexistent is not defined
            (drab) lib/drab/core.ex:100: Rebel.Core.exec_js!/2

        iex> socket |> exec_js!("for(i=0; i<1000000000; i++) {}")
        ** (Rebel.JSExecutionError) timed out after 5000 ms.
            (drab) lib/drab/core.ex:100: Rebel.Core.exec_js!/2

        iex> socket |> exec_js!("for(i=0; i<10000000; i++) {}", timeout: 1000)
        ** (Rebel.JSExecutionError) timed out after 1000 ms.
            lib/drab/core.ex:114: Rebel.Core.exec_js!/3

  """
  def exec_js!(socket, js, options \\ []) do
    case exec_js(socket, js, options) do
      {:ok, result} -> result
      {:error, message} -> raise Rebel.JSExecutionError, message: message
    end
  end

  @doc """
  Asynchronously broadcasts given javascript to all browsers listening on the given subject.

  The subject is derived from the first argument, which could be:

  * socket - in this case broadcasting option is derived from the setup in the commander.
    See `Rebel.Commander.broadcasting/1` for the broadcasting options

  * same_path(string) - sends the JS to browsers sharing (and configured as listening to same_path
    in `Rebel.Commander.broadcasting/1`) the same url

  * same_commander(atom) - broadcast goes to all browsers configured with :same_commander

  * same_topic(string) - broadcast goes to all browsers listening to this topic; notice: this
    is internal Rebel topic, not a Phoenix Socket topic

  First argument may be a list of the above.

  The second argument is a JavaScript string.

  See `Rebel.Commander.broadcasting/1` to find out how to change the listen subject.

      iex> Rebel.Core.broadcast_js(socket, "alert('Broadcasted!')")
      {:ok, :broadcasted}
      iex> Rebel.Core.broadcast_js(same_path("/drab/live"), "alert('Broadcasted!')")
      {:ok, :broadcasted}
      iex> Rebel.Core.broadcast_js(same_controller(MyApp.LiveController), "alert('Broadcasted!')")
      {:ok, :broadcasted}
      iex> Rebel.Core.broadcast_js(same_topic("my_topic"), "alert('Broadcasted!')")
      {:ok, :broadcasted}
      iex> Rebel.Core.broadcast_js([same_topic("my_topic"), same_path("/drab/live")], "alert('Broadcasted!')")
      {:ok, :broadcasted}

  Returns `{:ok, :broadcasted}`
  """
  def broadcast_js(subject, js, _options \\ []) do
    ret = Rebel.broadcast(subject, self(), "broadcastjs", js: js)
    {ret, :broadcasted}
  end

  @doc """
  Bang version of `Rebel.Core.broadcast_js/3`
  """
  def broadcast_js!(subject, js, _options \\ []) do
    Rebel.broadcast(subject, self(), "broadcastjs", js: js)
    subject
  end

  def set_event_handlers(socket, selector) do
    exec_js(socket, ~s/Rebel.set_event_handlers('#{selector}')/)
    socket
  end

  def set_event_handlers!(socket, selector) do
    broadcast_js(socket, ~s/Rebel.set_event_handlers('#{selector}')/)
    socket
  end

  def get_store(socket) do
    socket.assigns.__rebel_store
  end

  def get_store(socket, key) do
    socket.assigns.__rebel_store[key]
  end

  @doc """
  Returns the value of the Rebel store represented by the given key or `default` when key not found

      counter = get_store(socket, :counter, 0)
  """
  def get_store(socket, key, default) do
    get_store(socket, key) || default
  end

  # @doc """
  # Returns the value of the Rebel store represented by the given key.

  #     uid = get_store(socket, :user_id)
  # """
  # def get_store(socket, key) do
  #   store = Rebel.get_store(Rebel.pid(socket))
  #   store[key]
  #   # store(socket)[key]
  # end

  @doc """
  Saves the key => value in the Store. Returns unchanged socket.

      put_store(socket, :counter, 1)
  """
  def put_store(socket, key, value) do
    store = socket |> store() |> Map.merge(%{key => value})

    {:ok, _} =
      exec_js(
        socket,
        "Rebel.set_rebel_store_token(\"#{tokenize_store(socket, store)}\")"
      )

    # store the store in Rebel server, to have it on terminate
    save_store(socket, store)

    socket
  end

  def set_store(socket, store \\ %{}) do
    struct(socket, assigns: Map.put(socket.assigns, :__rebel_store, store))
  end

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
  def encode_js(value), do: Jason.encode!(value)

  @doc false
  def decode_js(value) do
    case Jason.decode(value) do
      {:ok, v} -> v
      _ -> value
    end
  end

  @doc false
  def save_store(socket, store) do
    Rebel.set_store(Rebel.pid(socket), store)
  end

  @doc false
  def save_socket(socket) do
    Rebel.set_socket(Rebel.pid(socket), socket)
  end

  @doc """
  Returns the value of the Plug Session represented by the given key.

      counter = get_session(socket, :userid)

  You must explicit which session keys you want to access in `:access_session` option in `use Rebel.Commander`.
  """
  def get_session(socket, key) do
    Rebel.get_session(socket.assigns.__rebel_pid)[key]
    # session(socket)[key]
  end

  @doc """
  Returns the value of the Plug Session represented by the given key or `
  default` when key not found

      counter = get_session(socket, :userid, 0)

  You must explicit which session keys you want to access in `
  :access_session` option in `use Rebel.Commander`.
  """
  def get_session(socket, key, default) do
    get_session(socket, key) || default
  end

  @doc false
  def save_session(socket, session) do
    Rebel.set_session(socket.assigns.__rebel_pid, session)
  end

  @doc false
  def store(socket) do
    name = socket.assigns.__channel_name
    # TODO: error {:error, "The operation is insecure."}
    case exec_js(socket, "Rebel.get_rebel_store_token('#{name}')") do
      {:ok, store_token} ->
        detokenize_store(socket, store_token)

      error ->
        if Application.get_env(:rebel, :logger) do
          Logger.warning("failed to get store name: #{inspect(name)}, error: #{inspect(error)}")
        end

        error
    end
  end

  @doc false
  def session(socket) do
    name = socket.assigns.__channel_name

    case exec_js(socket, "Rebel.get_rebel_session_token('#{name}')") do
      {:ok, session_token} ->
        detokenize_store(socket, session_token)

      error ->
        if Application.get_env(:rebel, :logger) do
          Logger.warning("failed to get session name: #{inspect(name)}, error: #{inspect(error)}")
        end

        error
    end
  end

  @doc false
  def tokenize_store(socket, store) do
    Rebel.tokenize(socket, store, "rebel_store_token")
  end

  # empty store
  defp detokenize_store(_socket, rebel_store_token) when rebel_store_token == nil, do: %{}

  defp detokenize_store(socket, rebel_store_token) do
    # we just ignore wrong token and defauklt the store to %{}
    # this is because it is read on connect, and raising here would cause infinite reconnects

    # set the token max age to 1 day by default
    max_age = Application.get_env(:rebel, :token_max_age, 86400)

    case Phoenix.Token.verify(socket, "rebel_store_token", rebel_store_token, max_age: max_age) do
      {:ok, rebel_store} ->
        rebel_store

      {:error, _reason} ->
        %{}
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

    unless id,
      do:
        raise(ArgumentError, """
        Try to use Rebel.Core.this!/1 on DOM object without an ID:
        #{inspect(sender)}
        """)

    "##{id}"
  end
end
