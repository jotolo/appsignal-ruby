# frozen_string_literal: true

require "json"
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
    option :json, type: :boolean, default: false,
      desc: "Print the box descriptor as JSON (for orchestrators)"
    option :anthropic_api_key, type: :string,
      desc: "Seed an Anthropic API key for unattended dispatch (defaults to $ANTHROPIC_API_KEY)"
    def up(name)
      ensure_docker!
      box = build_box(name)
      raise Error, "Box '#{name}' already exists. Use `gdkbox rm #{name}` first." if box.exists?
      api_key = resolve_api_key

      say "Spinning up GDK box '#{name}' (this pulls a large image on first run)...", :green unless options[:json]
      box.create!(
        image: options[:image],
        ssh_port: options[:ssh_port],
        web_port: options[:web_port],
        install_claude: options[:claude],
        api_key: api_key
      )
      rewrite_ssh_config

      if options[:json]
        puts JSON.generate(box.summary)
        return
      end

      say "\nBox '#{name}' is up.", :green
      print_connection_details(box)
      unless api_key
        say "\n  No Anthropic API key seeded. Before unattended dispatch, run:", :yellow
        say "    gdkbox set-key #{name}   (uses $ANTHROPIC_API_KEY)", :yellow
      end
    end

    desc "ls", "List all GDK boxes and their status"
    option :json, type: :boolean, default: false,
      desc: "Print the fleet as a JSON array (for orchestrators)"
    def ls
      boxes = Box.all(config: config).sort_by(&:name)
      docker = Docker.new

      if options[:json]
        summaries = boxes.map { |box| box.summary(state: docker.available? ? nil : "unknown") }
        puts JSON.generate(summaries)
        return
      end

      if boxes.empty?
        say "No GDK boxes yet. Create one with `gdkbox up <name>`."
        return
      end

      boxes.each do |box|
        status = docker.available? ? box.state : "unknown"
        say format("%-20s %-10s ssh:%-6s web:%-6s %s",
          box.name, status, box.ssh_port, box.web_port, box.web_url)
      end
    end

    desc "status NAME", "Show detailed status and connection info for a box"
    option :json, type: :boolean, default: false, desc: "Print the box descriptor as JSON"
    def status(name)
      box = load_box!(name)
      docker = Docker.new

      if options[:json]
        puts JSON.generate(box.summary(state: docker.available? ? nil : "unknown"))
        return
      end

      say "Box:        #{box.name}"
      say "Container:  #{box.container_name}"
      say "State:      #{docker.available? ? box.state : 'unknown'}"
      print_connection_details(box)
    end

    desc "dispatch NAME", "Dispatch a Claude Code agent task headlessly into the box"
    long_desc <<~DESC
      Runs `claude -p` non-interactively inside the box's GDK checkout and
      streams the agent's output. This is the primitive an orchestrator uses
      to hand a task to a box in the pool. Provide the task with --task or
      --task-file. Exit status mirrors the agent's.
    DESC
    option :task, type: :string, desc: "The task/prompt to give the agent"
    option :task_file, type: :string, desc: "Read the task from a local file"
    option :json, type: :boolean, default: false,
      desc: "Return Claude's structured JSON output"
    option :timeout, type: :numeric, desc: "Abort the agent after N seconds"
    option :yolo, type: :boolean, default: true,
      desc: "Skip permission prompts (safe in an isolated box)"
    def dispatch(name)
      box = load_box!(name)
      task = options[:task]
      task = File.read(options[:task_file]) if options[:task_file]
      raise Error, "Provide a task with --task or --task-file." if task.nil? || task.strip.empty?

      result = box.run_agent(
        task: task,
        json: options[:json],
        yolo: options[:yolo],
        timeout: options[:timeout]
      )
      $stdout.print(result.stdout)
      $stderr.print(result.stderr) unless result.stderr.to_s.empty?
      exit(result.status)
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

    desc "set-key NAME", "Seed or rotate the Anthropic API key inside the box"
    long_desc <<~DESC
      Stores an Anthropic API key inside the box so dispatched agents can
      authenticate without a human. The key is kept only inside the container
      (a 0600 file owned by the GDK user) and never in host-side metadata.
      Prefer passing it via the ANTHROPIC_API_KEY environment variable rather
      than --anthropic-api-key, which can be visible in shell history.
    DESC
    option :anthropic_api_key, type: :string,
      desc: "API key to seed (defaults to $ANTHROPIC_API_KEY)"
    def set_key(name)
      box = load_box!(name)
      api_key = resolve_api_key
      raise Error, "Provide --anthropic-api-key or set $ANTHROPIC_API_KEY." unless api_key

      say "Seeding Anthropic API key into '#{name}'...", :green
      box.set_api_key!(api_key)
      say "Done. Unattended `gdkbox dispatch #{name}` is ready.", :green
    end
    map "set-key" => :set_key

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

    # The API key from --anthropic-api-key, falling back to the environment.
    # Returns nil when neither is set or the value is blank.
    def resolve_api_key
      key = options[:anthropic_api_key]
      key = ENV["ANTHROPIC_API_KEY"] if key.nil? || key.strip.empty?
      key unless key.nil? || key.strip.empty?
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
