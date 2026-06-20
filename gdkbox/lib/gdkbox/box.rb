# frozen_string_literal: true

require "time"

module GDKBox
  # A single GDK-in-a-box instance: a Docker container plus its persisted
  # metadata. This is the orchestration layer the CLI talks to.
  class Box
    attr_reader :name, :config

    def initialize(name, config:, shell: Shell.new, docker: nil, store: nil, ssh_key: nil)
      @name = name
      @config = config
      @shell = shell
      @docker = docker || Docker.new(shell: shell)
      @store = store || Store.new(config: config)
      @ssh_key = ssh_key || SSHKey.new(config: config, shell: shell)
    end

    def self.all(config:, store: nil, **kwargs)
      store ||= Store.new(config: config)
      store.all.map { |data| from_data(data, config: config, store: store, **kwargs) }
    end

    def self.from_data(data, config:, **kwargs)
      box = new(data["name"], config: config, **kwargs)
      box.instance_variable_set(:@data, data)
      box
    end

    def data
      @data ||= @store.load(name)
    end

    def exists?
      @store.exists?(name)
    end

    def container_name
      data ? data["container_name"] : @config.container_name(name)
    end

    def ssh_port
      data && data["ssh_port"]
    end

    def web_port
      data && data["web_port"]
    end

    def web_url
      "http://127.0.0.1:#{web_port}"
    end

    def ssh_host_alias
      @config.ssh_host_alias(name)
    end

    def remote_path
      data ? data["remote_path"] : @config.remote_path
    end

    def state
      @docker.state(container_name)
    end

    # Provision a brand new box end to end: pull image, run container, enable
    # SSH, optionally install Claude Code, then persist metadata.
    def create!(image: nil, ssh_port: nil, web_port: nil, install_claude: true)
      raise Error, "Box '#{name}' already exists" if exists?

      image ||= @config.default_image
      ssh_port ||= next_port(Config::SSH_PORT_BASE)
      web_port ||= next_port(Config::WEB_PORT_BASE, exclude: [ssh_port])
      public_key = @ssh_key.ensure!
      cname = @config.container_name(name)

      @docker.pull(image)
      @docker.run_container(
        name: cname,
        image: image,
        publish: [
          "127.0.0.1:#{ssh_port}:#{Config::SSH_CONTAINER_PORT}",
          "127.0.0.1:#{web_port}:#{Config::GDK_WEB_CONTAINER_PORT}"
        ],
        labels: { "gdkbox" => "true", "gdkbox.name" => name }
      )

      provisioner = Provisioner.new(docker: @docker, config: @config)
      provisioner.setup_ssh(cname, public_key)
      provisioner.setup_claude(cname) if install_claude

      @data = {
        "name" => name,
        "container_name" => cname,
        "image" => image,
        "ssh_port" => ssh_port,
        "web_port" => web_port,
        "ssh_user" => @config.ssh_user,
        "remote_path" => @config.remote_path,
        "claude_installed" => install_claude,
        "created_at" => Time.now.utc.iso8601
      }
      @store.save(@data)
      @data
    end

    # Start a stopped box and make sure sshd is running again (processes
    # started via `docker exec` do not survive a container restart).
    def start!
      @docker.start(container_name)
      Provisioner.new(docker: @docker, config: @config)
        .setup_ssh(container_name, @ssh_key.ensure!)
    end

    def stop!
      @docker.stop(container_name)
    end

    def destroy!
      @docker.rm(container_name, force: true)
      @store.delete(name)
    end

    def install_claude!
      Provisioner.new(docker: @docker, config: @config).setup_claude(container_name)
      return unless data

      @data = data.merge("claude_installed" => true)
      @store.save(@data)
    end

    # argv to open an interactive SSH session using the generated config.
    def ssh_command
      ["ssh", ssh_host_alias]
    end

    private

    def next_port(base, exclude: [])
      used = @store.used_ports + exclude
      port = base
      port += 1 while used.include?(port)
      port
    end
  end
end
