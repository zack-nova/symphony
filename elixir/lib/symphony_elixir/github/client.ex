defmodule SymphonyElixir.GitHub.Client do
  @moduledoc """
  Thin GitHub Issues REST client for tracker polling and state updates.
  """

  require Logger

  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Issue

  @issue_page_size 100

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    with {:ok, params, assignee_filter} <- candidate_params(),
         {:ok, issues} <- fetch_issue_pages("open", params),
         {:ok, normalized_issues} <- normalize_scoped_issues(issues, assignee_filter) do
      normalized_issues
      |> filter_issues_by_states(Tracker.settings().active_states)
      |> then(&{:ok, &1})
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    states =
      state_names
      |> Enum.map(&normalize_label/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    Enum.reduce_while(states, {:ok, []}, fn state_name, {:ok, acc} ->
      with {:ok, issues} <- fetch_issue_pages("all", state_scope_params(state_name)),
           {:ok, normalized_issues} <- normalize_scoped_issues(issues) do
        {:cont, {:ok, normalized_issues ++ acc}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, issues} -> {:ok, Enum.uniq_by(issues, & &1.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    issue_ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn issue_id, {:ok, acc} ->
      case fetch_issue_state_by_id(issue_id) do
        {:ok, %Issue{} = issue} -> {:cont, {:ok, [issue | acc]}}
        :missing -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, issues} -> {:ok, Enum.reverse(issues)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    with {:ok, issue_number} <- issue_number(issue_id),
         {:ok, issue} <- fetch_issue(issue_number),
         :ok <- validate_issue_in_scope(issue, issue_id),
         {:ok, _body} <-
           request_json(:post, "/repos/#{repo_path()}/issues/#{issue_number}/comments",
             json: %{"body" => body},
             expected_statuses: [201]
           ) do
      :ok
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    with :ok <- validate_label_state_target(state_name),
         {:ok, issue_number} <- issue_number(issue_id),
         {:ok, issue} <- fetch_issue(issue_number),
         :ok <- validate_issue_in_scope(issue, issue_id),
         {:ok, labels} <- labels_after_state_transition(issue, issue_id, state_name),
         {:ok, _body} <-
           request_json(:put, "/repos/#{repo_path()}/issues/#{issue_number}/labels", json: %{"labels" => labels}),
         {:ok, _body} <-
           request_json(:patch, "/repos/#{repo_path()}/issues/#{issue_number}", json: %{"state" => github_issue_state(state_name)}) do
      :ok
    end
  end

  defp fetch_issue_pages(github_state, base_params) when github_state in ["all", "closed", "open"] do
    fetch_issue_pages(github_state, base_params, 1, [])
  end

  defp fetch_issue_pages(github_state, base_params, page, acc_issues) do
    params =
      base_params
      |> Map.merge(%{state: github_state, per_page: @issue_page_size, page: page})

    with {:ok, body} <- request_json(:get, "/repos/#{repo_path()}/issues", params: params),
         {:ok, issues} <- decode_issue_list(body) do
      updated_acc = Enum.reverse(issues, acc_issues)

      if length(issues) == @issue_page_size do
        fetch_issue_pages(github_state, base_params, page + 1, updated_acc)
      else
        {:ok, Enum.reverse(updated_acc)}
      end
    end
  end

  defp fetch_issue(issue_number) do
    request_json(:get, "/repos/#{repo_path()}/issues/#{issue_number}", [])
  end

  defp fetch_issue_state_by_id(issue_id) do
    with {:ok, issue_number} <- issue_number(issue_id),
         {:ok, issue} <- fetch_issue(issue_number) do
      case validate_issue_in_scope(issue, issue_id) do
        :ok -> normalize_scoped_issue(issue)
        {:error, {:issue_outside_tracker_scope, ^issue_id}} -> :missing
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp request_json(method, path, opts) when is_atom(method) and is_binary(path) and is_list(opts) do
    expected_statuses = Keyword.get(opts, :expected_statuses, [200])
    request_opts = Keyword.delete(opts, :expected_statuses)

    case github_request(method, path, request_opts) do
      {:ok, %{status: status} = response} ->
        if status in expected_statuses do
          {:ok, Map.get(response, :body)}
        else
          Logger.error("GitHub request failed status=#{status}")
          {:error, {:github_api_status, status}}
        end

      {:error, reason} ->
        Logger.error("GitHub request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  defp github_request(method, path, opts) do
    request_fun = Application.get_env(:symphony_elixir, :github_request_fun, &http_request/3)
    request_fun.(method, path, opts)
  end

  defp http_request(method, path, opts) do
    with {:ok, headers} <- rest_headers() do
      Req.request(
        [
          method: method,
          url: endpoint_url(path),
          headers: headers,
          connect_options: [timeout: 30_000]
        ] ++ opts
      )
    end
  end

  defp endpoint_url(path) do
    Tracker.options()
    |> Map.get("endpoint", "https://api.github.com")
    |> normalize_endpoint()
    |> Kernel.<>(path)
  end

  defp normalize_endpoint(endpoint) when is_binary(endpoint) do
    endpoint
    |> String.trim()
    |> String.trim_trailing("/")
    |> case do
      "" -> "https://api.github.com"
      normalized -> normalized
    end
  end

  defp normalize_endpoint(_endpoint), do: "https://api.github.com"

  defp rest_headers do
    case Tracker.settings().api_key do
      token when is_binary(token) ->
        {:ok,
         [
           {"Authorization", "Bearer #{token}"},
           {"Accept", "application/vnd.github+json"},
           {"X-GitHub-Api-Version", "2022-11-28"},
           {"Content-Type", "application/json"}
         ]}

      _ ->
        {:error, :missing_github_api_token}
    end
  end

  defp decode_issue_list(issues) when is_list(issues) do
    issues
    |> Enum.reject(&pull_request?/1)
    |> then(&{:ok, &1})
  end

  defp decode_issue_list(_unknown), do: {:error, :github_unknown_payload}

  defp normalize_scoped_issues(issues), do: normalize_scoped_issues(issues, nil)

  defp normalize_scoped_issues(issues, assignee_filter) when is_list(issues) do
    Enum.reduce_while(issues, {:ok, []}, fn issue, {:ok, acc} ->
      case normalize_scoped_issue(issue, assignee_filter) do
        {:ok, normalized_issue} -> {:cont, {:ok, [normalized_issue | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized_issues} -> {:ok, Enum.reverse(normalized_issues)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_scoped_issue(issue), do: normalize_scoped_issue(issue, nil)

  defp normalize_scoped_issue(issue, assignee_filter) when is_map(issue) do
    labels = extract_label_names(issue)
    issue_id = github_issue_identity(issue)

    with {:ok, state} <- label_state(labels, issue_id) do
      {:ok,
       %Issue{
         id: issue_id,
         identifier: issue_id,
         title: issue["title"],
         description: issue["body"],
         priority: nil,
         state: state,
         branch_name: nil,
         url: issue["html_url"],
         assignee_id: primary_assignee_login(issue),
         blocked_by: [],
         labels: Enum.map(labels, &normalize_label/1),
         assigned_to_worker: assigned_to_worker?(issue, assignee_filter),
         created_at: parse_datetime(issue["created_at"]),
         updated_at: parse_datetime(issue["updated_at"])
       }}
    end
  end

  defp normalize_scoped_issue(_issue, _assignee_filter), do: {:error, :github_unknown_payload}

  defp label_state(labels, issue_id) do
    state_labels =
      labels
      |> Enum.map(&normalize_label/1)
      |> Enum.filter(&String.starts_with?(&1, "state:"))
      |> Enum.uniq()

    case state_labels do
      [state] -> {:ok, state}
      [] -> {:error, {:invalid_label_state, issue_id, :missing}}
      states -> {:error, {:invalid_label_state, issue_id, {:multiple, states}}}
    end
  end

  defp validate_label_state_target(state_name) do
    if state_name |> normalize_label() |> String.starts_with?("state:") do
      :ok
    else
      {:error, {:invalid_label_state_target, state_name}}
    end
  end

  defp validate_issue_in_scope(issue, issue_id) do
    labels =
      issue
      |> extract_label_names()
      |> Enum.map(&normalize_label/1)
      |> MapSet.new()

    case Map.get(Tracker.options(), "scope") do
      %{"type" => "label", "label" => label} when is_binary(label) ->
        if MapSet.member?(labels, normalize_label(label)) do
          :ok
        else
          {:error, {:issue_outside_tracker_scope, issue_id}}
        end

      _ ->
        :ok
    end
  end

  defp labels_after_state_transition(issue, issue_id, state_name) do
    labels = extract_label_names(issue)

    with {:ok, _current_state} <- label_state(labels, issue_id) do
      labels =
        labels
        |> Enum.map(&normalize_label/1)
        |> Enum.reject(&String.starts_with?(&1, "state:"))
        |> Kernel.++([normalize_label(state_name)])
        |> Enum.uniq()

      {:ok, labels}
    end
  end

  defp filter_issues_by_states(issues, state_names) when is_list(issues) and is_list(state_names) do
    wanted_states =
      state_names
      |> Enum.map(&normalize_label/1)
      |> MapSet.new()

    Enum.filter(issues, fn
      %Issue{state: state_name} when is_binary(state_name) ->
        MapSet.member?(wanted_states, normalize_label(state_name))

      _ ->
        false
    end)
  end

  defp scope_params do
    case Map.get(Tracker.options(), "scope") do
      %{"type" => "label", "label" => label} when is_binary(label) ->
        %{labels: normalize_label(label)}

      _ ->
        %{}
    end
  end

  defp candidate_params do
    with {:ok, assignee_filter} <- assignee_filter() do
      {:ok, Map.merge(scope_params(), assignee_query_params(assignee_filter)), assignee_filter}
    end
  end

  defp assignee_filter do
    case Tracker.settings().assignee do
      nil ->
        {:ok, nil}

      assignee when is_binary(assignee) ->
        assignee
        |> String.trim()
        |> assignee_filter_for_value()
    end
  end

  defp assignee_filter_for_value(""), do: {:ok, nil}

  defp assignee_filter_for_value("me") do
    case request_json(:get, "/user", []) do
      {:ok, %{"login" => login}} when is_binary(login) ->
        {:ok, %{login: login}}

      {:ok, _body} ->
        {:error, :missing_github_viewer_identity}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp assignee_filter_for_value(assignee), do: {:ok, %{login: assignee}}

  defp assignee_query_params(nil), do: %{}
  defp assignee_query_params(%{login: login}) when is_binary(login), do: %{assignee: login}

  defp state_scope_params(state_name) do
    labels =
      case Map.get(Tracker.options(), "scope") do
        %{"type" => "label", "label" => label} when is_binary(label) ->
          [normalize_label(label), normalize_label(state_name)]

        _ ->
          [normalize_label(state_name)]
      end

    %{labels: Enum.join(labels, ",")}
  end

  defp github_issue_state(state_name) do
    terminal_states =
      Tracker.settings().terminal_states
      |> Enum.map(&normalize_label/1)
      |> MapSet.new()

    if MapSet.member?(terminal_states, normalize_label(state_name)) do
      "closed"
    else
      "open"
    end
  end

  defp issue_number(issue_id) when is_binary(issue_id) do
    prefix = repository_name() <> "#"

    if String.starts_with?(issue_id, prefix) do
      issue_id
      |> String.replace_prefix(prefix, "")
      |> issue_number_from_string(issue_id)
    else
      {:error, {:invalid_github_issue_id, issue_id}}
    end
  end

  defp issue_number_from_string(raw, issue_id) when is_binary(raw) do
    case Integer.parse(raw) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, {:invalid_github_issue_id, issue_id}}
    end
  end

  defp github_issue_identity(%{"number" => number}) when is_integer(number) and number > 0 do
    "#{repository_name()}##{number}"
  end

  defp github_issue_identity(_issue), do: nil

  defp repo_path do
    Tracker.options()
    |> Map.fetch!("repository")
    |> normalize_repository()
  end

  defp repository_name do
    Tracker.options()
    |> Map.fetch!("repository")
    |> String.trim()
  end

  defp normalize_repository(repository) when is_binary(repository) do
    case String.split(String.trim(repository), "/", parts: 2) do
      [owner, repo] -> "#{URI.encode(owner, &URI.char_unreserved?/1)}/#{URI.encode(repo, &URI.char_unreserved?/1)}"
      _ -> raise ArgumentError, message: "Invalid GitHub repository: #{inspect(repository)}"
    end
  end

  defp extract_label_names(%{"labels" => labels}) when is_list(labels) do
    labels
    |> Enum.map(fn
      %{"name" => name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_label_names(_issue), do: []

  defp pull_request?(%{"pull_request" => pull_request}) when is_map(pull_request), do: true
  defp pull_request?(_issue), do: false

  defp primary_assignee_login(%{"assignee" => %{"login" => login}}) when is_binary(login), do: login
  defp primary_assignee_login(%{"assignees" => [%{"login" => login} | _]}) when is_binary(login), do: login
  defp primary_assignee_login(_issue), do: nil

  defp assigned_to_worker?(_issue, nil), do: true

  defp assigned_to_worker?(issue, %{login: login}) when is_binary(login) do
    normalized_login = normalize_assignee(login)

    issue
    |> assignee_logins()
    |> Enum.any?(&(normalize_assignee(&1) == normalized_login))
  end

  defp assigned_to_worker?(_issue, _assignee_filter), do: false

  defp assignee_logins(%{"assignees" => assignees}) when is_list(assignees) do
    assignees
    |> Enum.map(fn
      %{"login" => login} when is_binary(login) -> login
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp assignee_logins(%{"assignee" => %{"login" => login}}) when is_binary(login), do: [login]
  defp assignee_logins(_issue), do: []

  defp normalize_assignee(assignee) when is_binary(assignee) do
    assignee
    |> String.trim()
    |> String.downcase()
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_raw), do: nil

  defp normalize_label(label) when is_binary(label) do
    label
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_label(label), do: label |> to_string() |> normalize_label()
end
