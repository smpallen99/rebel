defmodule Rebel.Channel.Config do
  @moduledoc false

  defstruct channel: nil,
    controller: nil,
    view: nil,
    onload: nil,
    onconnect: nil,
    ondisconnect: nil,
    # by default load Drab.Query and Drab.Modal
    modules: [],
    # modules: [LivePage.Query, LivePage.Modal, LivePage.Waiter],
    access_session: [],
    before_handler: [],
    after_handler: [],
    broadcasting: :same_path
end
