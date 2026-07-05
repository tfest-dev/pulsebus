defmodule Pulsebus.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Pulsebus.Router, []}
      ] ++ file_logger_children() ++ desktop_notify_children() ++ http_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: Pulsebus.Supervisor)
  end

  defp http_children do
    config = Application.get_env(:pulsebus, Pulsebus.HTTP, [])

    if Keyword.get(config, :enabled, true) do
      [
        {Plug.Cowboy,
         scheme: :http,
         plug: Pulsebus.HTTP.Router,
         options: [
           ip: Keyword.get(config, :ip, {127, 0, 0, 1}),
           port: Keyword.get(config, :port, 4040)
         ]}
      ]
    else
      []
    end
  end

  defp file_logger_children do
    config = Application.get_env(:pulsebus, :file_logger, [])

    if Keyword.get(config, :enabled, false) do
      [
        {Pulsebus.Subscribers.FileLogger,
         path: Keyword.get(config, :path, "pulsebus_events.jsonl"),
         patterns: Keyword.get(config, :patterns, ["*"])}
      ]
    else
      []
    end
  end

  defp desktop_notify_children do
    config = Application.get_env(:pulsebus, :desktop_notify, [])

    if Keyword.get(config, :enabled, false) do
      [
        {Pulsebus.Subscribers.DesktopNotify,
         command: Keyword.get(config, :command, "notify-send"),
         patterns:
           Keyword.get(config, :patterns, [
             "repo.tests.failed",
             "codex.run.finished",
             "website.deploy.finished"
           ])}
      ]
    else
      []
    end
  end
end
