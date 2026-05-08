defmodule SymphonyElixir.AgentRunner do
  @moduledoc """
  Executes a single tracker issue in its workspace with Codex.
  """

  require Logger
  alias SymphonyElixir.Codex.AppServer
  alias SymphonyElixir.{Config, PromptBuilder, Tracker, Workspace}
  alias SymphonyElixir.Tracker.Issue

  @type worker_host :: String.t() | nil

  @spec run(map(), pid() | nil, keyword()) :: :ok | no_return()
  def run(issue, codex_update_recipient \\ nil, opts \\ []) do
    # The orchestrator owns host retries so one worker lifetime never hops machines.
    worker_host = selected_worker_host(Keyword.get(opts, :worker_host), Config.settings!().worker.ssh_hosts)

    Logger.info("Starting agent run for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case run_on_worker_host(issue, codex_update_recipient, opts, worker_host) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Agent run failed for #{issue_context(issue)}: #{inspect(reason)}")
        raise RuntimeError, "Agent run failed for #{issue_context(issue)}: #{inspect(reason)}"
    end
  end

  defp run_on_worker_host(issue, codex_update_recipient, opts, worker_host) do
    Logger.info("Starting worker attempt for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case Workspace.create_for_issue(issue, worker_host) do
      {:ok, workspace} ->
        send_worker_runtime_info(codex_update_recipient, issue, worker_host, workspace)

        try do
          with :ok <- Workspace.run_before_run_hook(workspace, issue, worker_host) do
            run_codex_turns(workspace, issue, codex_update_recipient, opts, worker_host)
          end
        after
          Workspace.run_after_run_hook(workspace, issue, worker_host)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp codex_message_handler(recipient, issue) do
    fn message ->
      send_codex_update(recipient, issue, message)
    end
  end

  defp send_codex_update(recipient, %Issue{id: issue_id}, message)
       when is_binary(issue_id) and is_pid(recipient) do
    send(recipient, {:codex_worker_update, issue_id, message})
    :ok
  end

  defp send_codex_update(_recipient, _issue, _message), do: :ok

  defp send_worker_runtime_info(recipient, %Issue{id: issue_id}, worker_host, workspace)
       when is_binary(issue_id) and is_pid(recipient) and is_binary(workspace) do
    send(
      recipient,
      {:worker_runtime_info, issue_id,
       %{
         worker_host: worker_host,
         workspace_path: workspace
       }}
    )

    :ok
  end

  defp send_worker_runtime_info(_recipient, _issue, _worker_host, _workspace), do: :ok

  defp run_codex_turns(workspace, issue, codex_update_recipient, opts, worker_host) do
    max_turns = Keyword.get(opts, :max_turns, Config.settings!().agent.max_turns)
    issue_state_fetcher = Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issue_states_by_ids/1)

    with {:ok, session} <- AppServer.start_session(workspace, worker_host: worker_host) do
      try do
        context = %{
          app_session: session,
          workspace: workspace,
          codex_update_recipient: codex_update_recipient,
          opts: opts,
          issue_state_fetcher: issue_state_fetcher,
          max_turns: max_turns
        }

        do_run_codex_turns(context, issue, 1, nil)
      after
        AppServer.stop_session(session)
      end
    end
  end

  defp do_run_codex_turns(context, issue, turn_number, pending_state_guidance_issue) do
    pending_state_guidance_issue = drain_pending_state_guidance_refresh(pending_state_guidance_issue)

    with {:ok, prompt} <-
           build_turn_prompt_result(
             issue,
             context.opts,
             turn_number,
             context.max_turns,
             pending_state_guidance_issue
           ),
         {:ok, turn_session} <-
           AppServer.run_turn(
             context.app_session,
             prompt,
             issue,
             on_message: codex_message_handler(context.codex_update_recipient, issue),
             on_external_message: codex_external_message_handler(context.opts)
           ) do
      Logger.info(
        "Completed agent run for #{issue_context(issue)} " <>
          "session_id=#{turn_session[:session_id]} " <>
          "workspace=#{context.workspace} turn=#{turn_number}/#{context.max_turns}"
      )

      case continue_with_issue?(issue, context.issue_state_fetcher) do
        {:continue, refreshed_issue} when turn_number < context.max_turns ->
          Logger.info(
            "Continuing agent run for #{issue_context(refreshed_issue)} " <>
              "after normal turn completion turn=#{turn_number}/#{context.max_turns}"
          )

          do_run_codex_turns(context, refreshed_issue, turn_number + 1, nil)

        {:continue, refreshed_issue} ->
          Logger.info(
            "Reached agent.max_turns for #{issue_context(refreshed_issue)} " <>
              "with issue still active; returning control to orchestrator"
          )

          :ok

        {:done, _refreshed_issue} ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_turn_prompt_result(issue, opts, turn_number, max_turns, pending_state_guidance_issue) do
    {:ok, build_turn_prompt(issue, opts, turn_number, max_turns, pending_state_guidance_issue)}
  rescue
    error ->
      if match?(%Issue{}, pending_state_guidance_issue) do
        {:error, {:state_guidance_render_failed, Exception.message(error)}}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp build_turn_prompt(issue, opts, 1, _max_turns, _pending_state_guidance_issue), do: PromptBuilder.build_prompt(issue, opts)

  defp build_turn_prompt(_issue, opts, turn_number, max_turns, pending_state_guidance_issue) do
    continuation_guidance = """
    Continuation guidance:

    - The previous Codex turn completed normally, but the tracker issue is still in an active state.
    - This is continuation turn ##{turn_number} of #{max_turns} for the current agent run.
    - Resume from the current workspace and workpad state instead of restarting from scratch.
    - The original task instructions and prior turn context are already present in this thread, so do not restate them before acting.
    - Focus on the remaining ticket work and do not end the turn while the issue stays active unless you are truly blocked.
    """

    append_pending_state_guidance(continuation_guidance, pending_state_guidance_issue, opts)
  end

  defp append_pending_state_guidance(continuation_guidance, nil, _opts), do: continuation_guidance

  defp append_pending_state_guidance(continuation_guidance, %Issue{} = pending_state_guidance_issue, opts) do
    case build_active_state_guidance_refresh(pending_state_guidance_issue, opts) do
      guidance when is_binary(guidance) ->
        """
        #{String.trim_trailing(continuation_guidance)}

        #{guidance}
        """
        |> String.trim_trailing()

      nil ->
        continuation_guidance
    end
  end

  defp drain_pending_state_guidance_refresh(latest_issue) do
    receive do
      {:active_state_guidance_refresh, %Issue{} = refreshed_issue} ->
        drain_pending_state_guidance_refresh(refreshed_issue)
    after
      0 ->
        latest_issue
    end
  end

  defp codex_external_message_handler(opts) do
    fn
      {:active_state_guidance_refresh, %Issue{} = refreshed_issue}, turn_session ->
        send_active_state_guidance_refresh(refreshed_issue, turn_session, opts)

      _message, _turn_session ->
        :unhandled
    end
  end

  defp send_active_state_guidance_refresh(%Issue{} = refreshed_issue, turn_session, opts) do
    case build_active_state_guidance_refresh_result(refreshed_issue, opts) do
      {:ok, nil} ->
        :ok

      {:ok, guidance} ->
        steer_active_turn(turn_session, guidance)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_active_state_guidance_refresh_result(%Issue{} = refreshed_issue, opts) do
    {:ok, build_active_state_guidance_refresh(refreshed_issue, opts)}
  rescue
    error ->
      {:error, {:state_guidance_render_failed, Exception.message(error)}}
  end

  defp steer_active_turn(turn_session, guidance) do
    case AppServer.steer_turn(turn_session, turn_session.turn_id, guidance) do
      :ok -> :ok
      {:error, reason} -> {:error, {:state_guidance_refresh_failed, reason}}
    end
  rescue
    error ->
      {:error, {:state_guidance_refresh_failed, Exception.message(error)}}
  end

  defp build_active_state_guidance_refresh(%Issue{} = refreshed_issue, opts) do
    case PromptBuilder.build_state_guidance(refreshed_issue, Keyword.put(opts, :heading, "Updated state guidance for")) do
      guidance when is_binary(guidance) ->
        """
        #{guidance}

        This guidance supersedes earlier state guidance for this active run.
        """
        |> String.trim_trailing()

      nil ->
        nil
    end
  end

  defp continue_with_issue?(%Issue{id: issue_id} = issue, issue_state_fetcher) when is_binary(issue_id) do
    case issue_state_fetcher.([issue_id]) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        if active_issue_state?(refreshed_issue.state) do
          {:continue, refreshed_issue}
        else
          {:done, refreshed_issue}
        end

      {:ok, []} ->
        {:done, issue}

      {:error, reason} ->
        {:error, {:issue_state_refresh_failed, reason}}
    end
  end

  defp continue_with_issue?(issue, _issue_state_fetcher), do: {:done, issue}

  defp active_issue_state?(state_name) when is_binary(state_name) do
    normalized_state = normalize_issue_state(state_name)

    Config.settings!().tracker.active_states
    |> Enum.any?(fn active_state -> normalize_issue_state(active_state) == normalized_state end)
  end

  defp active_issue_state?(_state_name), do: false

  defp selected_worker_host(nil, []), do: nil

  defp selected_worker_host(preferred_host, configured_hosts) when is_list(configured_hosts) do
    hosts =
      configured_hosts
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case preferred_host do
      host when is_binary(host) and host != "" -> host
      _ when hosts == [] -> nil
      _ -> List.first(hosts)
    end
  end

  defp worker_host_for_log(nil), do: "local"
  defp worker_host_for_log(worker_host), do: worker_host

  defp normalize_issue_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp issue_context(%Issue{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end
end
