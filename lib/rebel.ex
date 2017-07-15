defmodule Rebel do
  @moduledoc """
  Documentation for Rebel.
  """

  @doc false
  def tokenize(socket, what, salt \\ "rebel token") do
    Phoenix.Token.sign(socket, salt, what)
  end

  @doc false
  def detokenize(socket, token, salt \\ "rebel token") do
    case Phoenix.Token.verify(socket, salt, token) do
      {:ok, detokenized} ->
        detokenized
      {:error, reason} ->
        raise "Can't verify the token `#{salt}`: #{inspect(reason)}" # let it die
    end
  end
end
