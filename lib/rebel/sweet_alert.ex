defmodule Rebel.SweetAlert do
  use Rebel.Module

  import Rebel.Template
  import Rebel.Core

  def prerequisites(), do: [Rebel.Query]
  # def js_templates(), do: ["drab.modal.js"]

  def swal_modal(socket, title, text, type, opts \\ [], callbacks \\ []) do
     swal socket, title, text, type, [{:modal, true} | opts], callbacks
  end
  def swal(socket, title, text, type, opts \\ [], callbacks \\ []) do
    # {confirm?, opts} = Keyword.pop(opts, :confirm_function)
    {modal?, opts} = Keyword.pop opts, :modal

    opts = Enum.map opts, fn
      {k, v} when is_binary(v) -> {k, ~s("#{v}")}
      {k, v} -> {k, v}
    end
    bindings =
      [
        title: title,
        text: text,
        type: type,
        opts: opts,
        confirm_function: callbacks != []
      ]

    js = render_template("modal.swal.js", bindings)
    |> String.replace("\n", "")
    # |> IO.inspect(label: "js")

    run socket, js, callbacks, modal?
    # case Rebel.push_and_wait_forever(socket, self(), "modal", js: js) do
    #   # {:ok, result} -> result
    #   {:ok, %{"result" => result} = params} = res ->
    #     result = String.to_existing_atom result
    #     if callback = callbacks[result] do
    #       callback.(params)
    #     else
    #       res
    #     end
    # end
  end

  defp run(socket, js, callbacks, true) do
    case Rebel.push_and_wait_forever(socket, self(), "modal", js: js) do
      {:ok, %{"result" => result} = params} = res ->
        result = String.to_existing_atom result
        if callback = callbacks[result] do
          callback.(params)
        else
          res
        end
    end
  end
  defp run(socket, js, _, _) do
    exec_js socket, js
  end

end
