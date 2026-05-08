defmodule SymphonyElixir.Tracker do
  @moduledoc """
  Adapter boundary for issue tracker reads and writes.
  """

  alias SymphonyElixir.Config

  @callback capabilities() :: map()
  @callback validate_settings(term()) :: :ok | {:error, term()}
  @callback fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  @callback update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}

  @spec settings() :: term()
  def settings do
    Config.settings!().tracker
  end

  @spec options() :: map()
  def options do
    settings().options
  end

  @spec validate_settings(term()) :: :ok | {:error, term()}
  def validate_settings(settings) do
    with {:ok, adapter} <- adapter_for_kind(settings.kind) do
      adapter.validate_settings(settings)
    end
  end

  @spec capabilities() :: map()
  def capabilities do
    adapter().capabilities()
  end

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues do
    adapter().fetch_candidate_issues()
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states) do
    adapter().fetch_issues_by_states(states)
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    adapter().fetch_issue_states_by_ids(issue_ids)
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) do
    adapter().create_comment(issue_id, body)
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) do
    adapter().update_issue_state(issue_id, state_name)
  end

  @spec adapter() :: module()
  def adapter do
    case adapter_for_kind(settings().kind) do
      {:ok, adapter} ->
        adapter

      {:error, reason} ->
        raise ArgumentError, message: "Invalid tracker adapter: #{inspect(reason)}"
    end
  end

  @spec adapter_for_kind(String.t() | nil) :: {:ok, module()} | {:error, term()}
  def adapter_for_kind(nil), do: {:error, :missing_tracker_kind}
  def adapter_for_kind("github"), do: {:ok, SymphonyElixir.GitHub.Adapter}
  def adapter_for_kind("linear"), do: {:ok, SymphonyElixir.Linear.Adapter}
  def adapter_for_kind("memory"), do: {:ok, SymphonyElixir.Tracker.Memory}
  def adapter_for_kind(kind), do: {:error, {:unsupported_tracker_kind, kind}}
end
