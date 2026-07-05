defmodule Pulsebus.Subscribers.DesktopNotify do
  @moduledoc """
  Subscriber process that sends local desktop notifications for matching events.
  """

  use GenServer

  require Logger

  @default_patterns [
    "repo.tests.failed",
    "codex.run.finished",
    "website.deploy.finished"
  ]

  def start_link(opts) do
    command = Keyword.get(opts, :command, "notify-send")
    patterns = Keyword.get(opts, :patterns, @default_patterns)
    router = Keyword.get(opts, :router, Pulsebus.Router)
    runner = Keyword.get(opts, :runner, &System.cmd/3)

    GenServer.start_link(
      __MODULE__,
      {command, patterns, router, runner},
      opts[:gen_server_opts] || []
    )
  end

  def format_notification(event) do
    title = "Pulsebus: #{event.topic}"
    body = "source=#{event.source} id=#{event.id}"

    {title, body}
  end

  def command_args(event) do
    {title, body} = format_notification(event)

    [title, body]
  end

  @impl true
  def init({command, patterns, router, runner}) do
    Enum.each(patterns, fn pattern ->
      :ok = Pulsebus.Router.subscribe(pattern, self(), router)
    end)

    {:ok, %{command: command, patterns: patterns, runner: runner}}
  end

  @impl true
  def handle_info({:pulsebus_event, event}, state) do
    args = command_args(event)

    case run_command(state.runner, state.command, args) do
      {:error, reason} ->
        Logger.error("[pulsebus] desktop notification command failed: #{inspect(reason)}")

      {_output, 0} ->
        :ok

      {_output, status} ->
        Logger.error("[pulsebus] desktop notification command failed with status #{status}")
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run_command(runner, command, args) do
    runner.(command, args, stderr_to_stdout: true)
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
