defmodule RekiWeb.PackageLive do
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
     |> assign(:package, nil)
     |> assign(:package_name, nil)
     |> assign(:not_found, false)}
  end

  @impl true
  def handle_params(%{"name" => encoded_name}, _uri, socket) do
    package_name = URI.decode(encoded_name)
    {:noreply, load_package(socket, package_name)}
  end

  @impl true
  def handle_info(:catalog_updated, socket) do
    {:noreply, load_package(socket, socket.assigns.package_name)}
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

  def status_badge_class(:approved), do: "bg-emerald-500/15 text-emerald-700 ring-emerald-600/20"
  def status_badge_class(:passed), do: "bg-emerald-500/15 text-emerald-700 ring-emerald-600/20"
  def status_badge_class(:queued), do: "bg-sky-500/15 text-sky-700 ring-sky-600/20"
  def status_badge_class(:running), do: "bg-indigo-500/15 text-indigo-700 ring-indigo-600/20"
  def status_badge_class(:pending), do: "bg-amber-500/15 text-amber-700 ring-amber-600/20"
  def status_badge_class(:blocked), do: "bg-rose-500/15 text-rose-700 ring-rose-600/20"
  def status_badge_class(:failed), do: "bg-rose-500/15 text-rose-700 ring-rose-600/20"
  def status_badge_class(:errored), do: "bg-rose-500/15 text-rose-700 ring-rose-600/20"
  def status_badge_class(:timed_out), do: "bg-rose-500/15 text-rose-700 ring-rose-600/20"
  def status_badge_class(:skipped), do: "bg-slate-500/15 text-slate-700 ring-slate-600/20"
  def status_badge_class(_status), do: "bg-slate-500/15 text-slate-700 ring-slate-600/20"

  def humanize_status(status) when is_atom(status) do
    status
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
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

  def format_timestamp(nil), do: "Not started"

  def format_timestamp(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_bytes(nil), do: "n/a"
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def encoded_package_path(name), do: "/packages/#{URI.encode(name)}"

  defp load_package(socket, nil), do: socket

  defp load_package(socket, package_name) do
    case Packages.get_package_for_catalog(package_name) do
      {:ok, package} ->
        socket
        |> assign(:package_name, package_name)
        |> assign(:package, package)
        |> assign(:not_found, false)

      {:error, :not_found} ->
        socket
        |> assign(:package_name, package_name)
        |> assign(:package, nil)
        |> assign(:not_found, true)
    end
  end
end
