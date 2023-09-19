defmodule Rebel.Query do
  require Logger

  @methods ~w(html text val width height innerWidth innerHeight outerWidth outerHeight position
                            offset scrollLeft scrollTop replaceWith)a
  @methods_plural ~w(htmls texts vals widths heights innerWidths innerHeights outerWidths outerHeights positions
                            offsets scrollLefts scrollTops)a
  @methods_with_argument ~w(attr prop css data)a
  @methods_with_argument_plural ~w(attrs props csses datas)a
  @insert_methods ~w(before after prepend append)a
  @broadcast &Rebel.Core.broadcast_js/2
  @no_broadcast &Rebel.Core.exec_js/2
  @html_modifiers ~r/html|append|before|after|insertAfter|insertBefore|htmlPrefilter|prepend|replaceWith|wrap/i

  @moduledoc """
  Rebel Module which provides interface to jQuery on the server side. You may query (`select/2`) or manipulate
  (`update/2`, `insert/2`, `delete/2`, `execute/2`) the selected DOM object.

  General syntax:

      return = socket |> select(what, from: selector)
      socket |> update(what, set: new_value, on: selector)
      socket |> insert(what, into: selector)
      socket |> delete(what, from: selector)
      socket |> execute(what, on: selector)

  where:
  * socket - websocket used in connection
  * selector - string with a DOM selector
  * what - a representation of jQuery method; an atom (eg. :html, :val) or key/value pair (like attr: name).
    An atom will launch the corresponding jQuey function without any arguments (eg. `.html()`). Key/value
    pair will launch the method named as the key with arguments taken from its value, so `text: "some"` becomes
    `.text("some")`.

  Object manipulation (`update/2`, `insert/2`, `delete/2`, `execute/2`) functions return socket.
  Query `select/2` returns either a found value (when using singular version of jQuery method, eg `:html`), or
  a Map of %{name|id|__undefined_XX => value}, when using plural - like `:htmls`.

  Select queries always refers to the page on which the event were launched. Data manipulation queries (`update/2`,
  `insert/2`, `delete/2`, `execute/2`) changes DOM objects on this page as well, but they have a broadcast versions:
  `update!/2`, `insert!/2`, `delete!/2` and `execute!/2`, which works the same, but changes DOM on every currently
  connected browsers, which has opened the same URL, same controller, or having the same channel topic (see
  `Rebel.Commander.broadcasting/1` to find out more).
  """

  # Rebel behaviour
  use Rebel.Module
  def js_templates(), do: ["rebel.events.js"]

  @doc false
  def transform_payload(payload, _state) do
    # TODO: change jQuery sender API to %{sender:, event:}
    # payload = Map.merge(payload["sender"], %{"event" => payload["event"]})

    # decode data values, just like jquery does
    d = payload["dataset"] || %{}

    d =
      Enum.map(d, fn {k, v} ->
        {k, Rebel.Core.decode_js(v)}
      end)
      |> Map.new()

    Map.merge(payload, %{"data" => d})
    |> Map.put_new("val", payload["value"])
  end

  # @doc """
  # Moved to `Rebel.Core.this/1`
  # """
  # def this(sender) do
  #   Rebel.Core.this(sender)
  # end

  # @doc """
  # Moved to `Rebel.Core.this!/1`
  # """
  # def this!(sender) do
  #   Rebel.Core.this!(sender)
  # end

  @doc """
  Returns a value get by executing jQuery `method` on selected DOM object, or
  a Map of %{name|id|__undefined_[INCREMENT]: value} when `method` name is plural, or a Map of
  `%{ method => returns_of_methods}`, when the method is `:all`.

  Plural version uses `name` attribute as a key, or `id`,  when there is no `name`,
  or `__undefined_[INCREMENT]`, when neither `id` or `name` are specified.

  In case the method requires an argument (like `attr()`), it should be given as key/value
  pair: method_name: "argument".

  Options:
  * from: "selector" - DOM selector which is queried
  * attr: "attribute" - DOM attribute
  * prop: "property" - DOM property
  * css: "css"
  * data: "att" - returns the value of jQuery `data("attr")` method

  Examples:
      name = socket |> select(:val, from: "#name")
      # "Stefan"
      name = socket |> select(:vals, from: "#name")
      # %{"name" => "Stefan"}
      font = socket |> select(css: "font", from: "#name")
      # "normal normal normal normal 14px / 20px \\"Helvetica Neue\\", Helvetica, Arial, sans-serif"
      button_ids = socket |> select(datas: "button_id", from: "button")
      # %{"button1" => 1, "button2" => 2}

  Available jQuery methods:
      html text val
      width height
      innerWidth innerHeight outerWidth outerHeight
      position offset scrollLeft scrollTop
      attr: val prop: val css: val data: val

  Available jQuery *plural* methods:
      htmls texts vals
      widths heights
      innerWidths innerHeights outerWidths outerHeights
      positions offsets scrollLefts scrollTops
      attrs: val props: val csses: val datas: val

  ## :all
  In case when method is `:all`, executes all known methods on the given selector. Returns
  Map `%{name|id => medthod_return_value}`. The Map key are generated in the same way as those with plural methods.

      socket |> select(:all, from: "span")
      %{"first_span" => %{"height" => 16, "html" => "First span with class qs_2", "innerHeight" => 20, ...

  Additionally, `id` and `name` attributes are included into a Map.
  """
  def select(socket, options)

  def select(socket, [{method, argument}, from: selector])
      when method in @methods_with_argument or method in @methods_with_argument_plural do
    do_query(socket, selector, jquery_method(method, argument), :select, @no_broadcast)
  end

  def select(_socket, [{method, argument}, from: selector]) do
    wrong_query!(selector, method, argument)
  end

  @doc "See `Rebel.Query.select/2`"
  def select(socket, method, options)

  def select(socket, method, from: selector)
      when method in @methods or method == :all or method in @methods_plural do
    do_query(socket, selector, jquery_method(method), :select, @no_broadcast)
  end

  def select(_socket, method, from: selector) do
    wrong_query!(selector, method)
  end

  @doc """
  Updates the DOM object corresponding to the jQuery `method`.

  In case when the method requires an argument (like `attr()`), it should be given as key/value pair:
  method_name: "argument".

  Waits for the browser to finish the changes, returns socket so it can be stacked.

  Options:
  * on: selector - DOM selector, on which the changes are made
  * set: value - new value
  * attr: attribute - DOM attribute
  * prop: property - DOM property
  * class: class - class name to be replaced by another class
  * css: updates a given css
  * data: sets the jQuery data storage by calling `data("key", value`); it *does not* update the `data-*` attribute

  Examples:
      socket |> update(:text, set: "saved...", on: "#save_button")
      socket |> update(attr: "style", set: "width: 100%", on: ".progress-bar")
      # the same effect:
      socket |> update(css: "width", set: "100%", on: ".progress-bar")

  Update can also switch the classes in DOM object (remove one and insert another):

      socket |> update(class: "btn-success", set: "btn-danger", on: "#save_button")

  You can also cycle between values - switch to the next value from the list
  or to the first element, if the actual value is not on the list:

      socket |> update(:text, set: ["One", "Two", "Three"], on: "#thebutton")
      socket |> update(css: "font-size", set: ["8px", "10px", "12px"], on: "#btn")

  When cycling through the `class` attribute, system will update the class if it is one in the list.
  In the other case, it will add the first from the list.

      socket |> update(:class, set: ["btn-success", "btn-danger"], on: "#btn")

  Please notice that cycling is only possible on selectors which returns one node.

  Another possibility is to toggle (add if not exists, remove in the other case) the class:

      socket |> update(:class, toggle: "btn-success", on: "#btn")

  Available jQuery methods: see `Rebel.Query.select/2`
  """
  def update(socket, attr: "data-" <> data, set: set, on: on) do
    data_attr_warn!(data, set, on)
    do_update(socket, @broadcast, attr: "data-" <> data, set: set, on: on)
  end

  def update(socket, prop: "data-" <> data, set: set, on: on) do
    data_attr_warn!(data, set, on)
    do_update(socket, @broadcast, prop: "data-" <> data, set: set, on: on)
  end

  def update(socket, options) do
    do_update(socket, @no_broadcast, options)
    socket
  end

  @doc "See `Rebel.Query.update/2`"
  def update(socket, method, options) do
    do_update(socket, @no_broadcast, method, options)
    socket
  end

  @doc """
  Like `Rebel.Query.update/2`, but broadcasts to all currently connected browsers.

  Broadcast functions are asynchronous, do not wait for the reply from browsers, immediately return socket.
  """
  def update!(socket, options) do
    do_update(socket, @broadcast, options)
    socket
  end

  @doc "See `Rebel.Query.update!/2`"
  def update!(socket, method, options) do
    do_update(socket, @broadcast, method, options)
    socket
  end

  defp do_update(socket, broadcast, [{method, argument}, set: values, on: selector])
       when method in @methods_with_argument do
    value = next_value(socket, values, method, argument, selector)
    {:ok, do_query(socket, selector, jquery_method(method, argument, value), :update, broadcast)}
  end

  defp do_update(socket, broadcast, class: from_class, set: to_class, on: selector) do
    if broadcast == @broadcast do
      socket
      |> insert!(class: to_class, into: selector)
      |> delete!(class: from_class, from: selector)
    else
      socket
      |> insert(class: to_class, into: selector)
      |> delete(class: from_class, from: selector)
    end
  end

  defp do_update(_socket, _broadcast, [{method, argument}, {:set, _value}, {:on, selector}]) do
    wrong_query!(selector, method, argument)
  end

  defp do_update(_socket, _broadcast, method, set: [], on: _selector) when method in @methods do
    {:ok, :nothing}
  end

  defp do_update(socket, broadcast, method, set: values, on: selector) when method in @methods do
    value = next_value(socket, values, method, selector)
    {:ok, do_query(socket, selector, jquery_method(method, value), :update, broadcast)}
  end

  defp do_update(socket, broadcast, :class, set: value, on: selector) when is_binary(value) do
    # shorthand for just a simple class update
    do_update(socket, broadcast, attr: "class", set: value, on: selector)
  end

  defp do_update(socket, broadcast, :class, toggle: value, on: selector) do
    {:ok, do_query(socket, selector, {:toggleClass, "(\"#{value}\")"}, :update, broadcast)}
  end

  defp do_update(socket, broadcast, :class, set: values, on: selector) when is_list(values) do
    # switch classes: updates the attr: "class" string with replacement of class, if it is on the list
    c = socket |> select(attrs: "class", from: selector)
    one_element_selector_only!(c, selector)

    classes = Map.values(c) |> Enum.map(&String.split/1) |> List.first()

    replaced =
      Enum.map(classes, fn c ->
        if c in values do
          next_in_list(values, c)
        else
          c
        end
      end)

    classes_together =
      if replaced == classes do
        [List.first(values) | classes]
      else
        replaced
      end
      |> Enum.join(" ")

    do_update(socket, broadcast, attr: "class", set: classes_together, on: selector)
  end

  defp do_update(_socket, _broadcast, method, set: value, on: selector) do
    wrong_query!(selector, method, value)
  end

  # returns next value of the given list (cycle) or the first element of the list
  defp next_value(socket, values, method, selector) when is_list(values) do
    v = socket |> select(plural(method), from: selector)
    one_element_selector_only!(v, selector)
    next_in_list(values, Map.values(v) |> List.first())
  end

  defp next_value(_socket, value, _method, _selector), do: value

  defp next_value(socket, values, method, argument, selector) when is_list(values) do
    v = socket |> select([{plural(method), argument}, from: selector])
    one_element_selector_only!(v, selector)
    next_in_list(values, Map.values(v) |> List.first())
  end

  defp next_value(_socket, value, _method, _argument, _selector), do: value

  defp next_in_list(list, value) do
    pos = value && Enum.find_index(list, &(&1 == value))

    if pos do
      Enum.at(list, rem(pos + 1, Enum.count(list)))
    else
      list |> List.first()
    end
  end

  defp one_element_selector_only!(v, selector) do
    # TODO: maybe it would be better to allow multiple-element cycling?
    if Enum.count(v) != 1 do
      raise ArgumentError,
            "Cycle is possible only on one element selector, given: \"#{selector}\""
    end
  end

  defp data_attr_warn!(data, set, on) do
    Logger.warning("""
    Updating data-* attribute or property is not recommended. You should use :data method instead:

        socket |> update(data: "#{data}", set: "#{set}", on: "#{on}")

    See https://github.com/grych/rebel/issues/14 to learn more.
    """)
  end

  @doc """
  Adds new node (html) or class to the selected object.

  Waits for the browser to finish the changes and returns socket so it can be stacked.

  Options:
  * class: class - class name to be inserted
  * into: selector - class will be added to specified selectors; only applies with `:class`
  * before: selector - creates html before the selector
  * after: selector - creates html node after the selector
  * append: selector - adds html to the end of the selector (inside the selector)
  * prepend: selector - adds html to the beginning of the selector (inside the selector)

  Example:
      socket |> insert(class: "btn-success", into: "#button")
      socket |> insert("<b>warning</b>", before: "#pane")
  """
  def insert(socket, options) do
    do_insert(socket, @no_broadcast, options)
    socket
  end

  @doc "See `Rebel.Query.insert/2`"
  def insert(socket, html, options) do
    do_insert(socket, @no_broadcast, html, options)
    socket
  end

  @doc """
  Like `Rebel.Query.insert/2`, but broadcast to all currently connected browsers.

  Broadcast functions are asynchronous, do not wait for the reply from browsers, immediately return socket.
  """
  def insert!(socket, options) do
    do_insert(socket, @broadcast, options)
    socket
  end

  @doc "See `Rebel.Query.insert/2`"
  def insert!(socket, html, options) do
    do_insert(socket, @broadcast, html, options)
    socket
  end

  defp do_insert(socket, broadcast, class: class, into: selector) do
    {:ok, do_query(socket, selector, jquery_method(:addClass, class), :insert, broadcast)}
  end

  defp do_insert(_socket, _broadcast, [{method, argument}, into: selector]) do
    wrong_query!(selector, method, argument)
  end

  defp do_insert(socket, broadcast, html, [{method, selector}]) when method in @insert_methods do
    {:ok, do_query(socket, selector, jquery_method(method, html), :insert, broadcast)}
  end

  defp do_insert(_socket, _broadcast, html, [{method, selector}]) do
    wrong_query!(html, method, selector)
  end

  @doc """
  Removes nodes, classes or attributes from selected node.

  With selector and no options, removes it and all its children. With given `from: selector` option, removes only
  the content, but element remains in the DOM tree. With options `class: class, from: selector` removes
  class from given node(s). Given option `prop: property` or `attr: attribute` it is able to remove
  property or attribute from the DOM node.

  Waits for the browser to finish the changes and returns socket so it can be stacked.

  Options:
  * class: class - class name to be deleted
  * prop: property - property to be removed from selected node(s)
  * attr: attribute - attribute to be deleted from selected node(s)
  * from: selector - DOM selector

  Example:
      socket |> delete(".btn")       # remove all `.btn`
      socket |> delete(from: "code") # empty all `<code>`, but node remains
      socket |> delete(class: "btn-success", from: "#button")
  """
  def delete(socket, options) do
    do_delete(socket, @no_broadcast, options)
    socket
  end

  @doc """
  Like `Dom.Query.delete/2`, but broadcasts to all currently connected browsers.

  Broadcast functions are asynchronous, do not wait for the reply from browsers, immediately return `:sent`.
  """
  def delete!(socket, options) do
    do_delete(socket, @broadcast, options)
    socket
  end

  defp do_delete(socket, broadcast, from: selector) do
    {:ok, do_query(socket, selector, jquery_method(:empty), :delete, broadcast)}
  end

  defp do_delete(socket, broadcast, class: class, from: selector) do
    {:ok, do_query(socket, selector, jquery_method(:removeClass, class), :delete, broadcast)}
  end

  defp do_delete(socket, broadcast, prop: property, from: selector) do
    {:ok, do_query(socket, selector, jquery_method(:removeProp, property), :delete, broadcast)}
  end

  defp do_delete(socket, broadcast, attr: attribute, from: selector) do
    {:ok, do_query(socket, selector, jquery_method(:removeAttr, attribute), :delete, broadcast)}
  end

  defp do_delete(_socket, _broadcast, [{method, argument}, from: selector]) do
    wrong_query!(selector, method, argument)
  end

  defp do_delete(socket, broadcast, selector) do
    {:ok, do_query(socket, selector, jquery_method(:remove), :delete, broadcast)}
  end

  @doc """
  Execute given jQuery method on selector. To be used in case built-in method calls are not enough.

  Waits for the browser to finish the changes and returns socket so it can be stacked.

      socket |> execute(:click, on: "#mybutton")
      socket |> execute(trigger: "click", on: "#mybutton")
      socket |> execute("trigger(\"click\")", on: "#mybutton")
  """
  def execute(socket, options) do
    do_execute(socket, @no_broadcast, options)
    socket
  end

  @doc """
  See `Rebel.Query.execute/2`
  """
  def execute(socket, method, options) do
    do_execute(socket, @no_broadcast, method, options)
    socket
  end

  @doc """
  Like `Rebel.Query.execute/2`, but broadcasts to all currently connected browsers, which have the same URL opened.

  Broadcast functions are asynchronous, do not wait for the reply from browsers, immediately return `:sent`.
  """
  def execute!(socket, options) do
    do_execute(socket, @broadcast, options)
    socket
  end

  @doc """
  See `Rebel.Query.execute!/2`
  """
  def execute!(socket, method, options) do
    do_execute(socket, @broadcast, method, options)
    socket
  end

  defp do_execute(socket, broadcast, [{method, parameter}, {:on, selector}]) do
    {:ok, do_query(socket, selector, jquery_method(method, parameter), :execute, broadcast)}
  end

  defp do_execute(socket, broadcast, method, on: selector) when is_atom(method) do
    # execute(socket, jquery_method(method), selector)
    {:ok, do_query(socket, selector, jquery_method(method), :execute, broadcast)}
  end

  defp do_execute(socket, broadcast, method, on: selector) when is_binary(method) do
    {:ok, do_query(socket, selector, method, :execute, broadcast)}
  end

  # Build and run general jQuery query
  defp do_query(socket, selector, method_jqueried, type, push_or_broadcast_function) do
    {:ok, return} = push_or_broadcast_function.(socket, build_js(selector, method_jqueried, type))
    return
  end

  defp jquery_method(method) do
    {method, "()"}
  end

  defp jquery_method(method, parameter) do
    {method, "(#{escape_value(parameter)})"}
  end

  defp jquery_method(method, attribute, parameter) do
    {method, "(#{escape_value(attribute)}, #{escape_value(parameter)})"}
  end

  # TODO: move it to templates

  defp build_js(selector, {:all, "()"}, :select) do
    # val: $(this).val(), html: $(this).html(), text: $(this).text()
    methods = Enum.map(@methods -- [:all], fn m -> "#{m}: $(this).#{m}()" end) |> Enum.join(", ")

    """
    var vals = {}
    var i = 0
    $('#{selector}').map(function() {
      var key = $(this).attr("name") || $(this).attr("id") || "__undefined_" + i++
      vals[key] = {#{methods}, id: $(this).attr('id'), name: $(this).attr('name')}
    })
    vals
    """
  end

  defp build_js(selector, {method, arguments}, :select)
       when method in @methods or method in @methods_with_argument do
    method_javascripted = Atom.to_string(method) <> arguments

    """
    $('#{selector}').#{method_javascripted}
    """
  end

  defp build_js(selector, {method, arguments}, :select)
       when method in @methods_plural or method in @methods_with_argument_plural do
    method_javascripted = Atom.to_string(singular(method)) <> arguments
    # """
    # $('#{selector}').map(function() {
    #   return $(this).#{method_javascripted}
    # }).toArray()
    # """
    """
    var vals = {}
    var i = 0
    $('#{selector}').map(function() {
      var key = $(this).attr("name") || $(this).attr("id") || "__undefined_" + i++
      vals[key] = $(this).#{method_javascripted}
    })
    vals
    """
  end

  defp build_js(selector, {method, arguments}, :select) do
    method_javascripted = Atom.to_string(method) <> arguments
    # """
    # $('#{selector}').map(function() {
    #   return $(this).#{method_javascripted}
    # }).toArray()
    # """
    """
    var vals = {}
    var i = 0
    $('#{selector}').map(function() {
      var key = $(this).attr("name") || $(this).attr("id") || "__undefined_" + i++
      vals[key] = $(this).#{method_javascripted}
    })
    vals
    """
  end

  defp build_js(selector, {method, arguments}, type)
       when type in ~w(update insert delete execute)a do
    method_javascripted = Atom.to_string(method) <> arguments
    # update events only when running .html() method
    update_events =
      if Regex.match?(@html_modifiers, method_javascripted) do
        "Rebel.set_event_handlers('#{selector}')"
      else
        ""
      end

    """
    $('#{selector}').#{method_javascripted}
    #{update_events}
    """
  end

  defp build_js(selector, method, type) when is_binary(method) and type == :execute do
    """
    $('#{selector}').#{method}
    """
  end

  defp singular(method) do
    # returns singular version of plural atom
    List.zip([
      @methods_plural ++ @methods_with_argument_plural,
      @methods ++ @methods_with_argument
    ])[method] || method
  end

  defp plural(method) do
    List.zip([
      @methods ++ @methods_with_argument,
      @methods_plural ++ @methods_with_argument_plural
    ])[method] || method
  end

  defp escape_value(value) when is_boolean(value), do: "#{inspect(value)}"
  defp escape_value(value) when is_nil(value), do: "\"\""
  defp escape_value(value), do: "#{Rebel.Core.encode_js(value)}"

  defp wrong_query!(selector, method, arguments \\ nil) do
    raise ArgumentError, """
    Rebel does not recognize your query:
      selector:  #{inspect(selector)}
      method:    #{inspect(method)}
      arguments: #{inspect(arguments)}
    """
  end
end
