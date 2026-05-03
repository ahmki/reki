defmodule RekiWeb.PackageVersionLive do
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
     |> assign(:version, nil)
     |> assign(:version_name, nil)
     |> assign(:not_found, false)}
  end

  @impl true
  def handle_params(%{"name" => encoded_name, "version" => version_name}, _uri, socket) do
    {:noreply, load_version(socket, URI.decode(encoded_name), version_name)}
  end

  @impl true
  def handle_info(:catalog_updated, socket) do
    {:noreply, load_version(socket, socket.assigns.package_name, socket.assigns.version_name)}
  end

  @impl true
  def handle_event("request_approval", %{"version" => version}, socket) do
    case Packages.request_approval(socket.assigns.package_name, version) do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Approval queued for #{version}.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Package version #{version} was not found.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue approval: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("approve_version", %{"version" => version}, socket) do
    case Packages.approve_version(socket.assigns.package_name, version) do
      {:ok, _package_version} ->
        {:noreply, put_flash(socket, :info, "#{version} approved.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Package version #{version} was not found.")}

      {:error, :already_decided} ->
        {:noreply, put_flash(socket, :error, "#{version} was already decided.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to approve #{version}: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("block_version", %{"version" => version}, socket) do
    case Packages.block_version(socket.assigns.package_name, version) do
      {:ok, _package_version} ->
        {:noreply, put_flash(socket, :info, "#{version} blocked.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Package version #{version} was not found.")}

      {:error, :already_decided} ->
        {:noreply, put_flash(socket, :error, "#{version} was already decided.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to block #{version}: #{inspect(reason)}")}
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

  def format_timestamp(nil), do: "Not started"
  def format_timestamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  def format_bytes(nil), do: "n/a"
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def approval_requestable?(version) do
    version.validation_status == :pending and not active_run?(version)
  end

  def approval_action_label(version) do
    cond do
      version.validation_status == :approved -> "Already approved"
      version.validation_status == :blocked -> "Blocked"
      active_run?(version) -> "Approval running"
      version.latest_run -> "Re-run approval"
      true -> "Run approval"
    end
  end

  def manual_decision_available?(version) do
    version.validation_status == :pending and not active_run?(version) and
      version.latest_run != nil
  end

  def encoded_package_path(name), do: "/packages/#{URI.encode(name)}"
  def encoded_version_path(name, version), do: "/packages/#{URI.encode(name)}/versions/#{version}"

  defp active_run?(version) do
    case version.latest_run do
      %{status: status} when status in [:queued, :running] -> true
      _ -> false
    end
  end

  defp load_version(socket, nil, _version_name), do: socket

  defp load_version(socket, package_name, version_name) do
    case Packages.get_package_version_for_catalog(package_name, version_name) do
      {:ok, %{package: package, version: version}} ->
        socket
        |> assign(:package_name, package_name)
        |> assign(:version_name, version_name)
        |> assign(:package, package)
        |> assign(:version, version)
        |> assign(:not_found, false)

      {:error, :not_found} ->
        socket
        |> assign(:package_name, package_name)
        |> assign(:version_name, version_name)
        |> assign(:package, nil)
        |> assign(:version, nil)
        |> assign(:not_found, true)
    end
  end
end
