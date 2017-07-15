defmodule Rebel.ControllerTest do
  use ExUnit.Case, async: true

  defmodule PageController do
    use Rebel.Controller
  end

  defmodule RoomController do
    use Rebel.Controller, channels: [
      Rebel.ControllerTest.RoomChannel,
      Rebel.ControllerTest.UserChannel,
    ]
  end

  test "__rebel__" do
    page = PageController.__rebel__()
    assert page[:channels] == [Rebel.ControllerTest.PageCommander]
    assert page[:controller] == Rebel.ControllerTest.PageController
    assert page[:view] == Rebel.ControllerTest.PageView
  end

  test "__rebel__ multiple commands" do
    page = RoomController.__rebel__()
    assert page[:channels] == [
      Rebel.ControllerTest.RoomChannel,
      Rebel.ControllerTest.UserChannel,
    ]
    assert page[:controller] == Rebel.ControllerTest.RoomController
    assert page[:view] == Rebel.ControllerTest.RoomView
  end
end
