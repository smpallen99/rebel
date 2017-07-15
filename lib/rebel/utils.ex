defmodule Rebel.Utils do
  @moduledoc """
  Utility Helpers
  """

  @doc """
  Infer module name from controller module
  """
  def get_module(module, target, destination) do
    [name | base] = module |> Module.split() |> Enum.reverse
    [String.replace(name, target, destination) | base]
    |> Enum.reverse
    |> Module.concat
  end
end
