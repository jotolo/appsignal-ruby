# frozen_string_literal: true

require "fileutils"

module GDKBox
  # Generates an SSH config fragment describing every box, and wires it into
  # the user's ~/.ssh/config via an Include directive.
  #
  # The fragment is regenerated wholesale from the current set of boxes on
  # every change, which keeps it consistent and easy to reason about. Each box
  # becomes a `Host gdkbox-<name>` entry that VS Code Remote-SSH and a plain
  # `ssh gdkbox-<name>` can both use.
  class SSHConfig
    HEADER = "# Managed by gdkbox - generated file, do not edit by hand"

    def initialize(config:)
      @config = config
    end

    def write(boxes)
      @config.ensure_dirs!
      File.write(@config.ssh_config_path, render(boxes))
      ensure_include!
    end

    def render(boxes)
      lines = [HEADER, ""]
      boxes.sort_by { |box| box["name"] }.each do |box|
        lines << "Host #{@config.ssh_host_alias(box['name'])}"
        lines << "  HostName 127.0.0.1"
        lines << "  Port #{box['ssh_port']}"
        lines << "  User #{box['ssh_user']}"
        lines << "  IdentityFile #{@config.private_key_path}"
        lines << "  IdentitiesOnly yes"
        lines << "  StrictHostKeyChecking no"
        lines << "  UserKnownHostsFile /dev/null"
        lines << ""
      end
      "#{lines.join("\n").rstrip}\n"
    end

    # Prepend an `Include` directive to ~/.ssh/config if it is not present.
    def ensure_include!
      path = @config.user_ssh_config
      include_line = "Include #{@config.ssh_config_path}"
      existing = File.exist?(path) ? File.read(path) : ""
      return if existing.include?(include_line)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{include_line}\n#{existing}")
    end
  end
end
