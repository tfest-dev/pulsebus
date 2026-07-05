import Config

config :pulsebus, Pulsebus.HTTP,
  enabled: true,
  ip: {127, 0, 0, 1},
  port: 4040

config :pulsebus, :file_logger,
  enabled: false,
  path: "pulsebus_events.jsonl",
  patterns: ["*"]

env_config = "#{config_env()}.exs"

if File.exists?(Path.join(__DIR__, env_config)) do
  import_config env_config
end
