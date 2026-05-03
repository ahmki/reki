defmodule RekiWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use RekiWeb, :html

  embed_templates "page_html/*"

  def package_status_class(package) do
    cond do
      package.approved_versions > 0 -> "bg-emerald-500/15 text-emerald-700 ring-emerald-600/20"
      package.pending_versions > 0 -> "bg-amber-500/15 text-amber-700 ring-amber-600/20"
      package.blocked_versions > 0 -> "bg-rose-500/15 text-rose-700 ring-rose-600/20"
      true -> "bg-slate-500/15 text-slate-700 ring-slate-600/20"
    end
  end

  def package_status_label(package) do
    cond do
      package.approved_versions > 0 -> "Installable"
      package.pending_versions > 0 -> "Awaiting approval"
      package.blocked_versions > 0 -> "Blocked"
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
end
