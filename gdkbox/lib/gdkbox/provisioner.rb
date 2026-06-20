# frozen_string_literal: true

module GDKBox
  # Runs the in-container setup steps: enabling SSH access and (optionally)
  # installing Claude Code. All steps are idempotent so they can be re-run
  # safely, for example after a `gdkbox start`.
  class Provisioner
    # Installs and starts sshd, then authorizes the gdkbox public key for the
    # GDK user. Values are passed via the environment to dodge shell quoting.
    SSH_SETUP = <<~'BASH'
      set -e
      if [ ! -x /usr/sbin/sshd ] && ! command -v sshd >/dev/null 2>&1; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server >/dev/null
      fi
      mkdir -p /run/sshd
      sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config || true
      install -d -m 700 -o "$GDKBOX_USER" -g "$GDKBOX_USER" "/home/$GDKBOX_USER/.ssh"
      printf '%s\n' "$GDKBOX_PUBKEY" > "/home/$GDKBOX_USER/.ssh/authorized_keys"
      chown "$GDKBOX_USER:$GDKBOX_USER" "/home/$GDKBOX_USER/.ssh/authorized_keys"
      chmod 600 "/home/$GDKBOX_USER/.ssh/authorized_keys"
      pgrep -x sshd >/dev/null 2>&1 || /usr/sbin/sshd
    BASH

    # Installs the Claude Code CLI globally via npm (present in the GDK image).
    CLAUDE_SETUP = <<~'BASH'
      set -e
      if command -v claude >/dev/null 2>&1; then
        echo "Claude Code already installed: $(claude --version 2>/dev/null || echo unknown)"
        exit 0
      fi
      if ! command -v npm >/dev/null 2>&1; then
        echo "npm not found in box; cannot install Claude Code" >&2
        exit 1
      fi
      npm install -g @anthropic-ai/claude-code
      claude --version || true
    BASH

    def initialize(docker:, config:)
      @docker = docker
      @config = config
    end

    def setup_ssh(container_name, public_key)
      @docker.exec(
        container_name, SSH_SETUP,
        user: "root",
        env: { "GDKBOX_USER" => @config.ssh_user, "GDKBOX_PUBKEY" => public_key }
      )
    end

    def setup_claude(container_name)
      @docker.exec(container_name, CLAUDE_SETUP, user: @config.ssh_user)
    end
  end
end
