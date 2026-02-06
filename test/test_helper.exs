# Set test environment
Application.put_env(:jido_coder_lib, :env, :test)

# Start ExUnit before cleanup (ExUnit starts the test supervision tree)
ExUnit.start()

# Clean up any existing test databases BEFORE starting the application
# This ensures tests start with a fresh schema

# Clean all jido test databases in /tmp
tmp_dir = System.tmp_dir!()

case File.ls(tmp_dir) do
  {:ok, files} ->
    Enum.each(files, fn file ->
      if String.starts_with?(file, "jido") do
        path = Path.join(tmp_dir, file)
        if File.dir?(path), do: File.rm_rf!(path)
      end
    end)

  _ ->
    :ok
end

# Clean the default data directory in case it's used
default_data_dir = Path.join([File.cwd!(), "data", "knowledge_graph"])

if File.exists?(default_data_dir) do
  File.rm_rf!(default_data_dir)
end

# Clean test/data directories that might have databases
test_data_dirs = [
  Path.join([File.cwd!(), "test", "data"]),
  Path.join([File.cwd!(), "test", "data", "kg_adapter_test"])
]

Enum.each(test_data_dirs, fn dir ->
  if File.exists?(dir), do: File.rm_rf!(dir)
end)

# Start the application for tests AFTER cleanup
Application.ensure_all_started(:jido_coder_lib)
