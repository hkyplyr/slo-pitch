defmodule SloPitch.Repo do
  use Ecto.Repo,
    otp_app: :slo_pitch,
    adapter: Ecto.Adapters.Postgres
end
