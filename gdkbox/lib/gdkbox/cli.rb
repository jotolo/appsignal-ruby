# frozen_string_literal: true

require "thor"
require "gdkbox"

module GDKBox
  # The `gdkbox` command-line interface.
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    class_option :verbose, type: :boolean, default: false,
      desc: "Print extra diagnostic output"

    desc "up NAME", "Spin up a new GDK box and wire it for SSH + VS Code"
    long_desc <<~DESC
      Pulls the official GDK-in-a-box image, starts a container named after
      NAME, enables SSH access using a dedicated gdkbox key, installs Claude
      Code inside the box, and registers a `Host gdkbox-NAME` entry so VS Code
      Remote-SSH can connect to it.
    DESC
    option :image, type: :string, desc: "Override the GDK image to use"
    option :ssh_port, type: :numeric, desc: "Host port to publish SSH on"
    option :web_port, type: :numeric, desc: "Host port to publish the GDK web UI on"
    option :claude, type: :boolean, default: true,
      desc: "Install Claude Code inside the box"
    def up(name)
      ensure_docker!
      box = build_box(name)
      raise Error, "Box '#{name}' already exists. Use `gdkbox rm #{name}` first." if box.exists?

      say "Spinning up GDK box '#{name}' (this pulls a large image on first run)...", :green
      box.create!(
        image: options[:image],
        ssh_port: options[:ssh_port],
        web_port: options[:web_port],
        install_claude: options[:claude]
      )
      rewrite_ssh_config

      say "\nBox '#{name}' is up.", :green
      print_connection_details(box)
    end

    desc "ls", "List all GDK boxes and their status"
    def ls
      boxes = Box.all(config: config)
      if boxes.empty?
        say "No GDK boxes yet. Create one with `gdkbox up <name>`."
        return
      end

      docker = Docker.new
      boxes.sort_by(&:name).each do |box|
        status = docker.available? ? box.state : "unknown"
        say format("%-20s %-10s ssh:%-6s web:%-6s %s",
          box.name, status, box.ssh_port, box.web_port, box.web_url)
      end
    end

    desc "status NAME", "Show detailed status and connection info for a box"
    def status(name)
      box = load_box!(name)
      say "Box:        #{box.name}"
      say "Container:  #{box.container_name}"
      say "State:      #{Docker.new.available? ? box.state : 'unknown'}"
      print_connection_details(box)
    end

    desc "ssh NAME", "Open an interactive SSH session into the box"
    def ssh(name)
      box = load_box!(name)
      exec(*box.ssh_command)
    end

    desc "code NAME", "Open the box in VS Code via Remote-SSH"
    def code(name)
      box = load_box!(name)
      rewrite_ssh_config
      vscode = VSCode.new
      unless vscode.available?
        say "The `code` CLI was not found on PATH.", :yellow
        say "Open VS Code manually and connect to host: #{box.ssh_host_alias}"
        say "Or run: #{vscode.open_command(box).join(' ')}"
        return
      end
      say "Opening #{box.name} in VS Code (#{box.ssh_host_alias})...", :green
      vscode.open(box)
    end

    desc "claude NAME", "Install Claude Code inside the box"
    def claude(name)
      box = load_box!(name)
      say "Installing Claude Code in '#{name}'...", :green
      box.install_claude!
      say "Done. SSH in and run `claude` to start an agent.", :green
    end

    desc "start NAME", "Start a stopped box (and re-enable SSH)"
    def start(name)
      box = load_box!(name)
      say "Starting '#{name}'...", :green
      box.start!
      print_connection_details(box)
    end

    desc "stop NAME", "Stop a running box"
    def stop(name)
      box = load_box!(name)
      say "Stopping '#{name}'...", :green
      box.stop!
    end

    desc "rm NAME", "Remove a box: its container, metadata, and SSH entry"
    option :force, type: :boolean, default: false, desc: "Skip confirmation"
    def rm(name)
      box = load_box!(name)
      unless options[:force]
        return unless yes?("Remove box '#{name}' and its container? [y/N]")
      end
      box.destroy!
      rewrite_ssh_config
      say "Removed '#{name}'.", :green
    end

    desc "version", "Print the gdkbox version"
    def version
      say GDKBox::VERSION
    end

    private

    def config
      @config ||= Config.new
    end

    def build_box(name)
      Box.new(name, config: config)
    end

    def load_box!(name)
      box = build_box(name)
      raise Error, "No box named '#{name}'. Run `gdkbox ls` to see boxes." unless box.exists?

      box
    end

    def ensure_docker!
      return if Docker.new.available?

      raise Error, "Docker does not appear to be installed or on PATH."
    end

    def rewrite_ssh_config
      SSHConfig.new(config: config).write(Store.new(config: config).all)
    end

    def print_connection_details(box)
      say ""
      say "  SSH:       ssh #{box.ssh_host_alias}", :cyan
      say "  VS Code:   gdkbox code #{box.name}", :cyan
      say "  Web UI:    #{box.web_url}", :cyan
      say "  Claude:    ssh #{box.ssh_host_alias} -t claude", :cyan
    end
  end
end
