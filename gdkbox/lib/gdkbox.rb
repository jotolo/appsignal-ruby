# frozen_string_literal: true

module GDKBox
  # Base error type for everything gdkbox raises.
  class Error < StandardError; end
end

require "gdkbox/version"
require "gdkbox/shell"
require "gdkbox/config"
require "gdkbox/docker"
require "gdkbox/store"
require "gdkbox/ssh_key"
require "gdkbox/ssh_config"
require "gdkbox/provisioner"
require "gdkbox/vscode"
require "gdkbox/box"
