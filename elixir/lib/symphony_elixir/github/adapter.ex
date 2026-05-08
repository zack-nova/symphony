defmodule SymphonyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub Issues-backed tracker adapter.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.GitHub.Client

  @spec capabilities() :: map()
  def capabilities do
    %{
      comments: true,
      state_updates: true,
      issue_sections: false,
      review_artifacts: false
    }
  end

  @spec validate_settings(term()) :: :ok | {:error, term()}
  def validate_settings(settings) do
    options = settings.options || %{}

    cond do
      not is_binary(settings.api_key) ->
        {:error, :missing_github_api_token}

      not valid_repository?(Map.get(options, "repository")) ->
        {:error, :missing_github_repository}

      true ->
        validate_github_settings(options, settings)
    end
  end

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues, do: client_module().fetch_candidate_issues()

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states), do: client_module().fetch_issues_by_states(states)

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids), do: client_module().fetch_issue_states_by_ids(issue_ids)

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body), do: client_module().create_comment(issue_id, body)

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name), do: client_module().update_issue_state(issue_id, state_name)

  defp client_module do
    Application.get_env(:symphony_elixir, :github_client_module, Client)
  end

  defp valid_repository?(repository) when is_binary(repository) do
    case String.split(String.trim(repository), "/", parts: 2) do
      [owner, repo] -> owner != "" and repo != ""
      _ -> false
    end
  end

  defp valid_repository?(_repository), do: false

  defp validate_scope(%{"type" => "repository"}), do: :ok

  defp validate_scope(%{"type" => "label", "label" => label}) when is_binary(label) do
    if label |> String.trim() |> String.downcase() |> String.starts_with?("project:") do
      :ok
    else
      {:error, :invalid_github_scope_label}
    end
  end

  defp validate_scope(nil), do: {:error, :missing_github_tracker_scope}
  defp validate_scope(_scope), do: {:error, :invalid_github_tracker_scope}

  defp validate_github_settings(options, settings) do
    with :ok <- validate_scope(Map.get(options, "scope")),
         :ok <- validate_state_set(:active_states, settings.active_states) do
      validate_state_set(:terminal_states, settings.terminal_states)
    end
  end

  defp validate_state_set(name, states) when is_list(states) do
    states
    |> Enum.find(&(not label_state?(&1)))
    |> case do
      nil -> :ok
      state -> {:error, {:invalid_github_state_set, name, state}}
    end
  end

  defp validate_state_set(name, _states), do: {:error, {:invalid_github_state_set, name, nil}}

  defp label_state?(state) when is_binary(state) do
    state
    |> String.trim()
    |> String.downcase()
    |> String.starts_with?("state:")
  end

  defp label_state?(_state), do: false
end
