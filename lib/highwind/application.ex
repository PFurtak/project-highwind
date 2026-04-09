defmodule Highwind.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HighwindWeb.Telemetry,
      Highwind.Repo,
      {DNSCluster, query: Application.get_env(:highwind, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Highwind.PubSub},
      # Start a worker by calling: Highwind.Worker.start_link(arg)
      # {Highwind.Worker, arg},
      # Start to serve requests, typically the last entry
      HighwindWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Highwind.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HighwindWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
