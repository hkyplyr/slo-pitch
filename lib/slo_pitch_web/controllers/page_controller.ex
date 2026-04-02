defmodule SloPitchWeb.PageController do
  use SloPitchWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
