defmodule Rebel.ReturnChannel do
  use Phoenix.Channel

  require Logger

  def join("return:" <> event, payload, socket) do
    {:ok, socket}
  end

  def handle_info({:rebel_return_assigns, assigns}, socket) do
    {:noreply, struct(socket, assigns: assigns)}
  end

  def handle_in("execjs", %{"ok" => [sender_encrypted, reply]}, socket) do
    # sender contains PID of the process which sent the query
    # sender is waiting for the result
    {sender, ref} = sender(socket, sender_encrypted)

    send(sender,
      { :got_results_from_client, :ok, ref, reply })

    {:noreply, socket}
  end

  def handle_in("modal", %{"ok" => [sender_encrypted, reply]}, socket) do
    # sender contains PID of the process which sent the query
    # sender is waiting for the result
    {sender, ref} = sender(socket, sender_encrypted)

    send(sender,
      { :got_results_from_client, :ok, ref, reply })

    {:noreply, socket}
  end

  def handle_in("execjs", %{"error" => [sender_encrypted, reply]}, socket) do
    {sender, ref} = sender(socket, sender_encrypted)

    send(sender,
      { :got_results_from_client, :error, ref, reply })

    {:noreply, socket}
  end

  defp sender(socket, sender_encrypted) do
    Rebel.detokenize(socket, sender_encrypted)
  end

end
