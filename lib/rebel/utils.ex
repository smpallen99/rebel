defmodule Rebel.Utils do
  @moduledoc """
  Utility Helpers
  """

  @doc """
  Infer module name from controller module
  """
  def get_module(module, target, destination) do
    [name | base] = module |> Module.split() |> Enum.reverse()

    [String.replace(name, target, destination) | base]
    |> Enum.reverse()
    |> Module.concat()
  end

  defmacro log(message) do
    quote do
      if level = Application.get_env(:rebel, :logger, false) do
        level = if level == true, do: :debug, else: level
        Logger.log(level, fn -> unquote(message) end)
      end
    end
  end
end
