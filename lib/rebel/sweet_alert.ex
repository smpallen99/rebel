defmodule Rebel.SweetAlert do
  use Rebel.Module

  import Rebel.Template

  def prerequisites(), do: [Rebel.Query]
  # def js_templates(), do: ["drab.modal.js"]

  def swal(socket, type, title, text, opts \\ [], callbacks \\ []) do
    # {confirm?, opts} = Keyword.pop(opts, :confirm_function)
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

    case Rebel.push_and_wait_forever(socket, self(), "modal", js: js) do
      # {:ok, result} -> result
      {:ok, %{"result" => result} = params} = res ->
        result = String.to_existing_atom result
        if callback = callbacks[result] do
          callback.(params)
        else
          res
        end
    end
  end

end
