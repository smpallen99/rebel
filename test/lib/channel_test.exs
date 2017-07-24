defmodule Rebel.ChannelTest do
  use ExUnit.Case, async: true

  defmodule PageChannel do
    use Rebel.Channel

    access_session [:user_id]
  end

  test "access_sessions" do
    assert Rebel.ChannelTest.PageChannel.__rebel__()[:access_session] == [:user_id]
  end

end
