# Rebel

Rebel is an <b>experimental project</b> based on a fork of Tomek Gryszkiewicz's amazing [Drab](https://github.com/grych/drab) project.

Rebel allows the programmer to program client side logic on the server with Elixir.

The incentive to create Rebel based on a Drab fork was for a project that mimics a single page application with on primary controller with multiple channels.

Rebel changes the Drab functionality by:

* Eliminating the Commander module
* Extending a Phoenix Channel to add the Drab functionality directly in a channel module.
* Adds support for using multiple Rebel channels for a single controller.
* Adds html markup to define which channel to run handlers on.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `rebel` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:rebel, "~> 0.1.0"}]
end
```
