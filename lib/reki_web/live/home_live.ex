defmodule RekiWeb.HomeLive do
  use RekiWeb, :live_view

  alias Reki.Packages

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Packages.subscribe_catalog()
    end

    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> load_catalog()}
  end

  @impl true
  def handle_info(:catalog_updated, socket) do
    {:noreply, load_catalog(socket)}
  end

  def package_status_class(package) do
    cond do
      package.latest_release_status == :queued ->
        "bg-sky-500/15 text-sky-700 ring-sky-600/20"

      package.latest_release_status == :running ->
        "bg-indigo-500/15 text-indigo-700 ring-indigo-600/20"

      package.latest_release_status == :pending ->
        "bg-amber-500/15 text-amber-700 ring-amber-600/20"

      package.latest_release_status == :blocked ->
        "bg-rose-500/15 text-rose-700 ring-rose-600/20"

      package.approved_versions > 0 ->
        "bg-emerald-500/15 text-emerald-700 ring-emerald-600/20"

      true ->
        "bg-slate-500/15 text-slate-700 ring-slate-600/20"
    end
  end

  def package_status_label(package) do
    cond do
      package.latest_release_status == :queued -> "Queued"
      package.latest_release_status == :running -> "Running checks"
      package.latest_release_status == :pending -> "Awaiting approval"
      package.latest_release_status == :blocked -> "Blocked"
      package.approved_versions > 0 -> "Installable"
      true -> "No releases"
    end
  end

  def relative_date(nil), do: "No releases yet"

  def relative_date(datetime) do
    days = Date.diff(Date.utc_today(), DateTime.to_date(datetime))

    cond do
      days == 0 -> "Today"
      days == 1 -> "Yesterday"
      true -> "#{days} days ago"
    end
  end

  defp load_catalog(socket) do
    packages = Packages.list_packages_for_catalog()

    stats = %{
      package_count: length(packages),
      approved_count: Enum.count(packages, &(&1.approved_versions > 0)),
      pending_count: Enum.sum(Enum.map(packages, & &1.pending_versions)),
      blocked_count: Enum.sum(Enum.map(packages, & &1.blocked_versions))
    }

    socket
    |> assign(:stats, stats)
    |> stream(:packages, packages, reset: true)
  end
end
