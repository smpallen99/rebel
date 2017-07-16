defmodule Rebel do
  @moduledoc """
  Documentation for Rebel.
  """

  @doc false
  def push_and_wait_for_response(socket, pid, message, payload \\ [], options \\ []) do
    ref = make_ref()
    push(socket, pid, ref, message, payload)
    timeout = options[:timeout] || Rebel.Config.get(:browser_response_timeout)
    receive do
      {:got_results_from_client, status, ^ref, reply} ->
        {status, reply}
      after timeout ->
        #TODO: message is still in a queue
        {:error, "timed out after #{timeout} ms."}
    end
  end

  @doc false
  def push_and_wait_forever(socket, pid, message, payload \\ []) do
    push(socket, pid, nil, message, payload)
    receive do
      {:got_results_from_client, status, _, reply} ->
        {status, reply}
    end
  end

  @doc false
  def push(socket, pid, ref, message, payload \\ []) do
    IO.inspect socket.assigns, label: "... assigns  "
    do_push_or_broadcast(socket, pid, ref, message, payload, &Phoenix.Channel.push/3)
  end

  @doc false
  def broadcast(subject, pid, message, payload \\ [])
  def broadcast(%Phoenix.Socket{} = socket, pid, message, payload) do
    do_push_or_broadcast(socket, pid, nil, message, payload, &Phoenix.Channel.broadcast/3)
  end

  def broadcast(subject, _pid, message, payload) when is_binary(subject) do
    Phoenix.Channel.Server.broadcast Rebel.Config.pubsub(), "__rebel:#{subject}", message, Map.new(payload)
  end

  def broadcast(topics, _pid, _ref, message, payload) when is_list(topics) do
    for topic <- topics do
      broadcast(topic, nil, message, payload)
    end
    :ok
  end

  defp do_push_or_broadcast(socket, pid, ref, message, payload, function) do
    m = payload |> Enum.into(%{}) |> Map.merge(%{sender: tokenize(socket, {pid, ref})})
    function.(socket, message, m)
  end

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
