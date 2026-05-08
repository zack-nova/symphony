defmodule SymphonyElixir.GitHubTrackerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.GitHub.Adapter, as: GitHubAdapter

  setup do
    github_request_fun = Application.get_env(:symphony_elixir, :github_request_fun)

    on_exit(fn ->
      if is_nil(github_request_fun) do
        Application.delete_env(:symphony_elixir, :github_request_fun)
      else
        Application.put_env(:symphony_elixir, :github_request_fun, github_request_fun)
      end
    end)

    :ok
  end

  test "fetches active GitHub issues inside label scope with normalized label state" do
    test_pid = self()

    Application.put_env(:symphony_elixir, :github_request_fun, fn method, path, opts ->
      send(test_pid, {:github_request, method, path, opts})

      {:ok,
       %{
         status: 200,
         body: [
           %{
             "number" => 123,
             "title" => "Build Orbit bridge",
             "body" => "Wire the tracker adapter.",
             "state" => "open",
             "html_url" => "https://github.com/owner/repo/issues/123",
             "labels" => [
               %{"name" => "project:orbit"},
               %{"name" => "State:Ready-For-Dev"},
               %{"name" => "type:feature"}
             ],
             "created_at" => "2026-05-06T01:02:03Z",
             "updated_at" => "2026-05-06T04:05:06Z"
           },
           %{
             "number" => 124,
             "title" => "Wait for design",
             "body" => nil,
             "state" => "open",
             "html_url" => "https://github.com/owner/repo/issues/124",
             "labels" => [
               %{"name" => "project:orbit"},
               %{"name" => "state:blocked"}
             ],
             "created_at" => "2026-05-06T02:02:03Z",
             "updated_at" => "2026-05-06T05:05:06Z"
           }
         ]
       }}
    end)

    write_github_workflow!()

    assert {:ok, [issue]} = Tracker.fetch_candidate_issues()

    assert %Issue{
             id: "owner/repo#123",
             identifier: "owner/repo#123",
             title: "Build Orbit bridge",
             description: "Wire the tracker adapter.",
             state: "state:ready-for-dev",
             url: "https://github.com/owner/repo/issues/123",
             labels: ["project:orbit", "state:ready-for-dev", "type:feature"],
             assigned_to_worker: true
           } = issue

    assert %DateTime{} = issue.created_at
    assert %DateTime{} = issue.updated_at

    assert_receive {:github_request, :get, "/repos/owner/repo/issues", opts}
    assert opts[:params] == %{labels: "project:orbit", page: 1, per_page: 100, state: "open"}
  end

  test "validates GitHub tracker settings shape" do
    base_settings = %{
      api_key: "github-token",
      options: %{
        "repository" => "owner/repo",
        "scope" => %{"type" => "label", "label" => "project:orbit"}
      },
      active_states: ["state:ready-for-dev"],
      terminal_states: ["state:merged"]
    }

    assert :ok = GitHubAdapter.validate_settings(base_settings)

    assert :ok =
             GitHubAdapter.validate_settings(%{
               base_settings
               | options: %{"repository" => "owner/repo", "scope" => %{"type" => "repository"}}
             })

    assert {:error, :missing_github_api_token} =
             GitHubAdapter.validate_settings(%{base_settings | api_key: nil})

    assert {:error, :missing_github_repository} =
             GitHubAdapter.validate_settings(%{
               base_settings
               | options: %{"scope" => %{"type" => "repository"}}
             })

    assert {:error, :missing_github_repository} =
             GitHubAdapter.validate_settings(%{
               base_settings
               | options: %{"repository" => "owner", "scope" => %{"type" => "repository"}}
             })

    assert {:error, :missing_github_tracker_scope} =
             GitHubAdapter.validate_settings(%{
               base_settings
               | options: %{"repository" => "owner/repo"}
             })

    assert {:error, :invalid_github_tracker_scope} =
             GitHubAdapter.validate_settings(%{
               base_settings
               | options: %{"repository" => "owner/repo", "scope" => %{"type" => "milestone"}}
             })

    assert {:error, :invalid_github_scope_label} =
             GitHubAdapter.validate_settings(%{
               base_settings
               | options: %{
                   "repository" => "owner/repo",
                   "scope" => %{"type" => "label", "label" => "type:bug"}
                 }
             })

    assert {:error, {:invalid_github_state_set, :active_states, nil}} =
             GitHubAdapter.validate_settings(%{base_settings | active_states: nil})

    assert {:error, {:invalid_github_state_set, :active_states, 123}} =
             GitHubAdapter.validate_settings(%{base_settings | active_states: [123]})
  end

  test "resolves assignee me before fetching candidate GitHub issues" do
    test_pid = self()

    Application.put_env(:symphony_elixir, :github_request_fun, fn
      :get, "/user", opts ->
        send(test_pid, {:github_request, :get, "/user", opts})
        {:ok, %{status: 200, body: %{"login" => "codex-runner"}}}

      :get, "/repos/owner/repo/issues", opts ->
        send(test_pid, {:github_request, :get, "/repos/owner/repo/issues", opts})

        {:ok,
         %{
           status: 200,
           body: [
             %{
               "number" => 127,
               "title" => "Assigned work",
               "body" => nil,
               "state" => "open",
               "html_url" => "https://github.com/owner/repo/issues/127",
               "labels" => [
                 %{"name" => "project:orbit"},
                 %{"name" => "state:ready-for-dev"}
               ],
               "assignees" => [%{"login" => "codex-runner"}]
             },
             %{
               "number" => 128,
               "title" => "Someone else's work",
               "body" => nil,
               "state" => "open",
               "html_url" => "https://github.com/owner/repo/issues/128",
               "labels" => [
                 %{"name" => "project:orbit"},
                 %{"name" => "state:ready-for-dev"}
               ],
               "assignees" => [%{"login" => "other-runner"}]
             }
           ]
         }}
    end)

    write_github_workflow!(assignee: "me")

    assert {:ok,
            [
              %Issue{id: "owner/repo#127", assigned_to_worker: true},
              %Issue{id: "owner/repo#128", assigned_to_worker: false}
            ]} = Tracker.fetch_candidate_issues()

    assert_receive {:github_request, :get, "/user", []}
    assert_receive {:github_request, :get, "/repos/owner/repo/issues", opts}
    assert opts[:params][:assignee] == "codex-runner"
  end

  test "fails candidate polling when a scoped open issue has no label state" do
    test_pid = self()

    Application.put_env(:symphony_elixir, :github_request_fun, fn method, path, opts ->
      send(test_pid, {:github_request, method, path, opts})

      {:ok,
       %{
         status: 200,
         body: [
           %{
             "number" => 125,
             "title" => "Missing state",
             "body" => nil,
             "state" => "open",
             "html_url" => "https://github.com/owner/repo/issues/125",
             "labels" => [
               %{"name" => "project:orbit"},
               %{"name" => "type:bug"}
             ]
           }
         ]
       }}
    end)

    write_github_workflow!()

    assert {:error, {:invalid_label_state, "owner/repo#125", :missing}} = Tracker.fetch_candidate_issues()
  end

  test "fails candidate polling when a scoped open issue has multiple label states" do
    Application.put_env(:symphony_elixir, :github_request_fun, fn _method, _path, _opts ->
      {:ok,
       %{
         status: 200,
         body: [
           %{
             "number" => 126,
             "title" => "Conflicting states",
             "body" => nil,
             "state" => "open",
             "html_url" => "https://github.com/owner/repo/issues/126",
             "labels" => [
               %{"name" => "project:orbit"},
               %{"name" => "state:ready-for-dev"},
               %{"name" => "State:In-Progress"}
             ]
           }
         ]
       }}
    end)

    write_github_workflow!()

    assert {:error, {:invalid_label_state, "owner/repo#126", {:multiple, ["state:ready-for-dev", "state:in-progress"]}}} =
             Tracker.fetch_candidate_issues()
  end

  test "updates a GitHub label state while preserving scope and ordinary labels" do
    test_pid = self()

    Application.put_env(:symphony_elixir, :github_request_fun, fn
      :get, "/repos/owner/repo/issues/123", opts ->
        send(test_pid, {:github_request, :get, "/repos/owner/repo/issues/123", opts})

        {:ok,
         %{
           status: 200,
           body: %{
             "number" => 123,
             "title" => "Build Orbit bridge",
             "body" => nil,
             "state" => "open",
             "html_url" => "https://github.com/owner/repo/issues/123",
             "labels" => [
               %{"name" => "project:orbit"},
               %{"name" => "state:ready-for-dev"},
               %{"name" => "type:feature"}
             ]
           }
         }}

      :put, "/repos/owner/repo/issues/123/labels", opts ->
        send(test_pid, {:github_request, :put, "/repos/owner/repo/issues/123/labels", opts})
        {:ok, %{status: 200, body: %{"labels" => opts[:json]["labels"]}}}

      :patch, "/repos/owner/repo/issues/123", opts ->
        send(test_pid, {:github_request, :patch, "/repos/owner/repo/issues/123", opts})
        {:ok, %{status: 200, body: %{}}}
    end)

    write_github_workflow!()

    assert :ok = Tracker.update_issue_state("owner/repo#123", "state:merged")

    assert_receive {:github_request, :get, "/repos/owner/repo/issues/123", _opts}
    assert_receive {:github_request, :put, "/repos/owner/repo/issues/123/labels", put_opts}
    assert_receive {:github_request, :patch, "/repos/owner/repo/issues/123", patch_opts}

    assert MapSet.new(put_opts[:json]["labels"]) ==
             MapSet.new(["project:orbit", "type:feature", "state:merged"])

    assert patch_opts[:json] == %{"state" => "closed"}
  end

  test "fetches current states for running GitHub issues by tracker issue identity" do
    Application.put_env(:symphony_elixir, :github_request_fun, fn
      :get, "/repos/owner/repo/issues/123", _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "number" => 123,
             "title" => "Build Orbit bridge",
             "body" => nil,
             "state" => "open",
             "html_url" => "https://github.com/owner/repo/issues/123",
             "labels" => [
               %{"name" => "project:orbit"},
               %{"name" => "state:in-progress"}
             ]
           }
         }}
    end)

    write_github_workflow!()

    assert {:ok, [%Issue{id: "owner/repo#123", state: "state:in-progress"}]} =
             Tracker.fetch_issue_states_by_ids(["owner/repo#123"])
  end

  test "treats running GitHub issues outside scope as no longer visible" do
    Application.put_env(:symphony_elixir, :github_request_fun, fn
      :get, "/repos/owner/repo/issues/123", _opts ->
        {:ok,
         %{
           status: 200,
           body: %{
             "number" => 123,
             "title" => "Build Orbit bridge",
             "body" => nil,
             "state" => "open",
             "html_url" => "https://github.com/owner/repo/issues/123",
             "labels" => [
               %{"name" => "state:in-progress"}
             ]
           }
         }}
    end)

    write_github_workflow!()

    assert {:ok, []} = Tracker.fetch_issue_states_by_ids(["owner/repo#123"])
  end

  test "fetches GitHub issues by label states for terminal cleanup" do
    test_pid = self()

    Application.put_env(:symphony_elixir, :github_request_fun, fn method, path, opts ->
      send(test_pid, {:github_request, method, path, opts})

      {:ok,
       %{
         status: 200,
         body: [
           %{
             "number" => 130,
             "title" => "Already merged",
             "body" => nil,
             "state" => "closed",
             "html_url" => "https://github.com/owner/repo/issues/130",
             "labels" => [
               %{"name" => "project:orbit"},
               %{"name" => "state:merged"}
             ]
           }
         ]
       }}
    end)

    write_github_workflow!()

    assert {:ok, [%Issue{id: "owner/repo#130", state: "state:merged"}]} =
             Tracker.fetch_issues_by_states(["state:merged"])

    assert_receive {:github_request, :get, "/repos/owner/repo/issues", opts}
    assert opts[:params] == %{labels: "project:orbit,state:merged", page: 1, per_page: 100, state: "all"}
  end

  test "creates a GitHub issue comment" do
    test_pid = self()

    Application.put_env(:symphony_elixir, :github_request_fun, fn
      :get, "/repos/owner/repo/issues/123", opts ->
        send(test_pid, {:github_request, :get, "/repos/owner/repo/issues/123", opts})

        {:ok,
         %{
           status: 200,
           body: %{
             "number" => 123,
             "labels" => [%{"name" => "project:orbit"}]
           }
         }}

      :post, "/repos/owner/repo/issues/123/comments", opts ->
        send(test_pid, {:github_request, :post, "/repos/owner/repo/issues/123/comments", opts})
        {:ok, %{status: 201, body: %{}}}
    end)

    write_github_workflow!()

    assert :ok = Tracker.create_comment("owner/repo#123", "hello from symphony")

    assert_receive {:github_request, :get, "/repos/owner/repo/issues/123", _opts}
    assert_receive {:github_request, :post, "/repos/owner/repo/issues/123/comments", opts}
    assert opts[:json] == %{"body" => "hello from symphony"}
  end

  test "does not create a GitHub issue comment outside label scope" do
    test_pid = self()

    Application.put_env(:symphony_elixir, :github_request_fun, fn
      :get, "/repos/owner/repo/issues/123", opts ->
        send(test_pid, {:github_request, :get, "/repos/owner/repo/issues/123", opts})

        {:ok,
         %{
           status: 200,
           body: %{
             "number" => 123,
             "labels" => [%{"name" => "state:ready-for-dev"}]
           }
         }}
    end)

    write_github_workflow!()

    assert {:error, {:issue_outside_tracker_scope, "owner/repo#123"}} =
             Tracker.create_comment("owner/repo#123", "hello from symphony")

    assert_receive {:github_request, :get, "/repos/owner/repo/issues/123", _opts}
    refute_receive {:github_request, :post, _path, _opts}
  end

  defp write_github_workflow!(opts \\ []) do
    assignee_yaml =
      case Keyword.get(opts, :assignee) do
        assignee when is_binary(assignee) -> ~s("#{assignee}")
        _ -> "null"
      end

    workflow = """
    ---
    tracker:
      kind: github
      active_states: ["state:ready-for-dev", "state:in-progress"]
      terminal_states: ["state:merged"]
      options:
        repository: "owner/repo"
        api_key: "github-token"
        scope:
          type: label
          label: "project:orbit"
        assignee: #{assignee_yaml}
    ---
    You are an agent for this repository.
    """

    File.write!(Workflow.workflow_file_path(), workflow)
    assert :ok = WorkflowStore.force_reload()
  end
end
