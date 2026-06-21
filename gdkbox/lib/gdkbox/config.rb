# frozen_string_literal: true

require "fileutils"

module GDKBox
  # Central configuration: filesystem paths, defaults, and naming conventions.
  #
  # The home directory can be overridden with the GDKBOX_HOME environment
  # variable (useful for tests and for running multiple isolated setups).
  class Config
    # The official "GDK in a box" container image published by GitLab.
    DEFAULT_IMAGE =
      "registry.gitlab.com/gitlab-org/gitlab-development-kit/gitlab-development-kit:main"

    CONTAINER_PREFIX = "gdkbox-"
    HOST_ALIAS_PREFIX = "gdkbox-"

    # Inside the official image GDK lives under the `gdk` user.
    SSH_USER = "gdk"
    REMOTE_PATH = "/home/gdk/gdk"

    # Ports as seen from inside the container.
    SSH_CONTAINER_PORT = 22
    GDK_WEB_CONTAINER_PORT = 3000

    # Starting points for the host-side published ports. Each new box claims
    # the next free port at or above these bases.
    SSH_PORT_BASE = 2222
    WEB_PORT_BASE = 3000

    attr_reader :home

    def initialize(home: nil)
      @home = File.expand_path(
        home || ENV["GDKBOX_HOME"] || File.join(Dir.home, ".gdkbox")
      )
    end

    def boxes_dir
      File.join(home, "boxes")
    end

    def keys_dir
      File.join(home, "keys")
    end

    def ssh_config_path
      File.join(home, "ssh_config")
    end

    def private_key_path
      File.join(keys_dir, "id_ed25519")
    end

    def public_key_path
      "#{private_key_path}.pub"
    end

    def user_ssh_config
      File.join(Dir.home, ".ssh", "config")
    end

    def ensure_dirs!
      FileUtils.mkdir_p(boxes_dir)
      FileUtils.mkdir_p(keys_dir)
    end

    def container_name(name)
      "#{CONTAINER_PREFIX}#{name}"
    end

    def ssh_host_alias(name)
      "#{HOST_ALIAS_PREFIX}#{name}"
    end

    def ssh_user
      SSH_USER
    end

    def remote_path
      REMOTE_PATH
    end

    def default_image
      ENV["GDKBOX_IMAGE"] || DEFAULT_IMAGE
    end
  end
end
