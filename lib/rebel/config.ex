defmodule Rebel.Config do
  @moduledoc """
  Drab configuration related functions.
  """

  @name :rebel

  def get(:templates_path),
    do: Application.get_env(@name, :templates_path, "priv/templates/#{@name}")
  def get(:socket),
    do: Application.get_env(@name, :socket, "/socket")
  def get(:browser_response_timeout),
    do: Application.get_env(@name, :browser_response_timeout, 5000)
  def get(_), do: nil
end
