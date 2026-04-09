defmodule HighwindWeb.MissionControlLiveTest do
  use HighwindWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "mounts and renders at root path", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Project Highwind"
    assert html =~ "Mission Control"
  end

  test "page title is set", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert page_title(view) =~ "Highwind"
  end
end
