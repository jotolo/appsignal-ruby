# frozen_string_literal: true

module GDKBox
  # Bridges a box to VS Code's Remote-SSH support.
  #
  # Because each box already has a `Host gdkbox-<name>` entry in the generated
  # SSH config, opening it is just a matter of pointing the `code` CLI at the
  # matching `ssh-remote+` authority.
  class VSCode
    def initialize(shell: Shell.new)
      @shell = shell
    end

    def available?
      !@shell.which("code").nil?
    end

    def open_command(box)
      ["code", "--remote", "ssh-remote+#{box.ssh_host_alias}", box.remote_path]
    end

    def open(box)
      @shell.run!(*open_command(box))
    end
  end
end
