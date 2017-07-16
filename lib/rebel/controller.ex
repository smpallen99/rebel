defmodule Rebel.Controller do

  defmacro __using__(options) do
    quote bind_quoted: [options: options] do
      Module.put_attribute(__MODULE__, :__rebel_opts__, options)
      unless Module.defines?(__MODULE__, {:__rebel__, 0}) do
        def __rebel__() do
          import Rebel.Utils
          # default commander is named as a controller
          view =  get_module(__MODULE__, "Controller", "View")
          channels =
            case @__rebel_opts__[:channels] do
              nil ->
                [get_module(__MODULE__, "Controller", "Commander")]
              list ->
                list
            end
          opts =
            if @__rebel_opts__[:default_channel] do
              @__rebel_opts__
            else
              [{:default_channel, (hd channels).name()} | @__rebel_opts__]
            end

          Enum.into(opts, %{channels: channels, view: view, controller: __MODULE__})
        end
      end
    end
  end
end
