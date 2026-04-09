defmodule Highwind.Repo do
  use Ecto.Repo,
    otp_app: :highwind,
    adapter: Ecto.Adapters.Postgres
end
