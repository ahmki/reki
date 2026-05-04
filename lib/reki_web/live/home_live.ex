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
     |> assign_import_form()
     |> load_catalog()}
  end

  @impl true
  def handle_info(:catalog_updated, socket) do
    {:noreply, load_catalog(socket)}
  end

  @impl true
  def handle_event("import_package", %{"import" => params}, socket) do
    name = String.trim(params["name"] || "")
    version = String.trim(params["version"] || "")

    case validate_import_params(name, version) do
      :ok ->
        case Packages.import_from_upstream(name, version) do
          {:ok, _package_version} ->
            {:noreply,
             socket
             |> put_flash(:info, "Imported #{name}@#{version} and queued approval.")
             |> push_navigate(to: encoded_version_path(name, version))}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, import_error_message(name, version, reason))
             |> assign_import_form(%{"name" => name, "version" => version})}
        end

      {:error, message} ->
        {:noreply,
         socket
         |> put_flash(:error, message)
         |> assign_import_form(%{"name" => name, "version" => version})}
    end
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

  def format_timestamp(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_bytes(nil), do: "n/a"

  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  def format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def encoded_package_path(name), do: "/packages/#{URI.encode(name)}"
  def encoded_version_path(name, version), do: "/packages/#{URI.encode(name)}/versions/#{version}"

  def import_form_defaults do
    %{"name" => "", "version" => ""}
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

  defp assign_import_form(socket, params \\ import_form_defaults()) do
    assign(socket, :import_form, to_form(params, as: :import))
  end

  defp validate_import_params(name, version) do
    cond do
      name == "" -> {:error, "Package name is required."}
      version == "" -> {:error, "Exact version is required."}
      true -> :ok
    end
  end

  defp import_error_message(name, version, :already_exists),
    do: "Package version already exists: #{name}@#{version}."

  defp import_error_message(name, _version, :upstream_not_found),
    do: "Upstream package not found: #{name}."

  defp import_error_message(name, version, :upstream_version_not_found),
    do: "Upstream version not found: #{name}@#{version}."

  defp import_error_message(_name, _version, :invalid_upstream_payload),
    do: "Upstream registry returned an invalid package payload."

  defp import_error_message(_name, _version, :upstream_tarball_not_found),
    do: "Upstream tarball could not be downloaded."

  defp import_error_message(_name, _version, reason),
    do: "Failed to import package: #{inspect(reason)}"
end
