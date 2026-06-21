# frozen_string_literal: true

module GDKBox
  # Manages a dedicated ed25519 keypair used to authenticate into boxes.
  #
  # gdkbox keeps its own key under the gdkbox home rather than touching the
  # user's personal keys. The public half is installed into each box; the
  # private half is referenced from the generated SSH config.
  class SSHKey
    def initialize(config:, shell: Shell.new)
      @config = config
      @shell = shell
    end

    # Generate the keypair if it does not yet exist, returning the public key.
    def ensure!
      return public_key if File.exist?(@config.public_key_path)

      @config.ensure_dirs!
      unless @shell.which("ssh-keygen")
        raise Error, "ssh-keygen not found on PATH; cannot generate an SSH key"
      end

      @shell.run!(
        "ssh-keygen", "-t", "ed25519",
        "-N", "", "-C", "gdkbox",
        "-f", @config.private_key_path
      )
      public_key
    end

    def public_key
      File.read(@config.public_key_path).strip
    end
  end
end
