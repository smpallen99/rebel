defmodule Rebel.Config do
  @moduledoc """
  Drab configuration related functions.
  """

  @name :rebel

  @app_module Mix.Project.get! |> Module.split |> hd |> Module.concat(nil)
  @app_name Mix.Project.config()[:app]

  @doc """
  Returns the name of the client Phoenix Application

      iex> Rebel.Config.app_name()
      :drab
  """
  def app_name() do
    @app_name
  end

  @doc """
  Returns the PubSub module of the client Phoenix Application

      iex> Drab.Config.pubsub()
      DrabTestApp.PubSub
  """
  def pubsub() do
    #TODO: what if the module is called differently?
    Module.concat(app_module(), PubSub)
  end

  @doc """
  Returns the Phoenix Application module atom

      iex> Rebel.Config.app_module()
      DrabTestApp
  """
  def app_module() do
    @app_module
  end

  @doc """
  Returns all environment for the default main Application

      iex> is_list(Drab.Config.app_config())
      true
  """
  def app_env() do
    Application.get_all_env(app_name())
  end

  @doc """
  Returns any config key for current main Application

      iex> Drab.app_config(:secret_key_base)
      "bP1ZF+DDZiAVGuIixHSboET1g18BPO4HeZnggJA/7q"
  """
  def app_config(config_key) do
    Keyword.fetch!(app_env(), endpoint()) |> Keyword.fetch!(config_key)
  end

  @doc """
  Returns the config for current main Application

      iex> is_list(Drab.Config.app_config())
      true
  """
  def app_config() do
    Keyword.fetch!(app_env(), endpoint())
  end

  def endpoint do
    Application.get_env(:rebel, :endpoint, Module.concat(app_module(), Endpoint))
  end

  def get(:templates_path),
    do: Application.get_env(@name, :templates_path, "priv/templates/#{@name}")

  def get(:socket),
    do: Application.get_env(@name, :socket, "/socket")

  def get(:browser_response_timeout),
    do: Application.get_env(@name, :browser_response_timeout, 5000)

  def get(:rebel_store_storage),
    do: Application.get_env(@name, :rebel_store_storage, :session_storage)

  def get(_), do: nil
end
