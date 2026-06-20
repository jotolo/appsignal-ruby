# frozen_string_literal: true

module GDKBox
  # A small, focused wrapper around the `docker` CLI.
  #
  # Only the verbs gdkbox needs are exposed. Every container created by gdkbox
  # is tagged with the `gdkbox=true` label plus a `gdkbox.name` label so they
  # can be discovered later without relying on local metadata alone.
  class Docker
    def initialize(shell: Shell.new)
      @shell = shell
    end

    def available?
      !@shell.which("docker").nil?
    end

    def pull(image)
      @shell.run!("docker", "pull", image)
    end

    # Start a detached container, returning its id.
    def run_container(name:, image:, publish: [], labels: {}, env: {}, args: [])
      cmd = ["docker", "run", "-d", "--name", name]
      labels.each { |key, value| cmd.push("--label", "#{key}=#{value}") }
      env.each { |key, value| cmd.push("-e", "#{key}=#{value}") }
      publish.each { |mapping| cmd.push("-p", mapping) }
      cmd << image
      cmd.concat(args)
      @shell.run!(*cmd).stdout.strip
    end

    # Run a bash script inside a running container. The script is passed to
    # `bash -lc` as a single argument; values that vary (keys, usernames) are
    # passed through the environment to avoid quoting pitfalls.
    def exec(name, script, user: nil, env: {}, input: nil)
      cmd = ["docker", "exec", "-i"]
      cmd.push("-u", user) if user
      env.each { |key, value| cmd.push("-e", "#{key}=#{value}") }
      cmd.push(name, "bash", "-lc", script)
      @shell.run!(*cmd, input: input)
    end

    def start(name)
      @shell.run!("docker", "start", name)
    end

    def stop(name)
      @shell.run!("docker", "stop", name)
    end

    def rm(name, force: true)
      cmd = ["docker", "rm"]
      cmd << "-f" if force
      cmd << name
      @shell.run(*cmd)
    end

    # The container's lifecycle state, or :absent if it does not exist.
    def state(name)
      result = @shell.run("docker", "inspect", "-f", "{{.State.Status}}", name)
      return :absent unless result.success?

      result.stdout.strip.to_sym
    end

    # Names of all gdkbox-managed containers, derived from labels.
    def list_names
      result = @shell.run(
        "docker", "ps", "-a",
        "--filter", "label=gdkbox=true",
        "--format", '{{index .Labels "gdkbox.name"}}'
      )
      return [] unless result.success?

      result.stdout.split("\n").map(&:strip).reject(&:empty?)
    end
  end
end
