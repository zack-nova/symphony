defmodule SymphonyElixir.PromptBuilder do
  @moduledoc """
  Builds agent prompts from normalized tracker issue data.
  """

  alias SymphonyElixir.{Config, Workflow}

  @render_opts [strict_variables: true, strict_filters: true]

  @spec build_prompt(SymphonyElixir.Tracker.Issue.t(), keyword()) :: String.t()
  def build_prompt(issue, opts \\ []) do
    template =
      Workflow.current()
      |> prompt_template!()
      |> append_state_prompt(issue)
      |> parse_template!()

    template
    |> Solid.render!(
      %{
        "attempt" => Keyword.get(opts, :attempt),
        "issue" => issue |> Map.from_struct() |> to_solid_map()
      },
      @render_opts
    )
    |> IO.iodata_to_binary()
  end

  defp prompt_template!({:ok, %{prompt_template: prompt}}), do: default_prompt(prompt)

  defp prompt_template!({:error, reason}) do
    raise RuntimeError, "workflow_unavailable: #{inspect(reason)}"
  end

  defp parse_template!(prompt) when is_binary(prompt) do
    Solid.parse!(prompt)
  rescue
    error ->
      reraise %RuntimeError{
                message: "template_parse_error: #{Exception.message(error)} template=#{inspect(prompt)}"
              },
              __STACKTRACE__
  end

  defp to_solid_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_solid_value(value)} end)
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_map()
  defp to_solid_value(value) when is_map(value), do: to_solid_map(value)
  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp default_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      Config.workflow_prompt()
    else
      prompt
    end
  end

  defp append_state_prompt(prompt, issue) when is_binary(prompt) do
    case state_prompt_for(issue) do
      prompt_variant when is_binary(prompt_variant) ->
        """
        #{String.trim_trailing(prompt)}

        State guidance for #{issue.state}:

        #{prompt_variant}
        """
        |> String.trim_trailing()

      nil ->
        prompt
    end
  end

  defp state_prompt_for(%{state: state}) when is_binary(state) do
    state_prompts()
    |> Map.get(normalize_state_key(state))
    |> normalize_state_prompt()
  end

  defp state_prompt_for(_issue), do: nil

  defp state_prompts do
    case Config.settings() do
      {:ok, settings} ->
        settings.agent.state_prompts
        |> normalize_state_prompt_keys()

      {:error, _reason} ->
        %{}
    end
  end

  defp normalize_state_prompt_keys(prompts) when is_map(prompts) do
    Map.new(prompts, fn {state, prompt} -> {normalize_state_key(state), prompt} end)
  end

  defp normalize_state_prompt_keys(_prompts), do: %{}

  defp normalize_state_key(state) do
    state
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_state_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "", do: nil, else: prompt
  end

  defp normalize_state_prompt(_prompt), do: nil
end
