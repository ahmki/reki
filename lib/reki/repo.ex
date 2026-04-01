defmodule Reki.Repo do
  use Ecto.Repo,
    otp_app: :reki,
    adapter: Ecto.Adapters.Postgres
end
