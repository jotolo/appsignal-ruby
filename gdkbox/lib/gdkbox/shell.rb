# frozen_string_literal: true

require "open3"

module GDKBox
  # Raised when a shelled-out command exits non-zero.
  class CommandError < Error
    attr_reader :command, :status, :stderr

    def initialize(command, status, stderr)
      @command = Array(command)
      @status = status
      @stderr = stderr
      super("Command failed (exit #{status}): #{@command.join(' ')}\n#{stderr}".strip)
    end
  end

  # Thin wrapper around shelling out to external commands.
  #
  # All arguments are passed as an explicit argv array (never a single
  # interpolated string) so user-supplied values cannot be interpreted by a
  # shell. Tests inject a fake that records the commands instead of running
  # them.
  class Shell
    Result = Struct.new(:stdout, :stderr, :status) do
      def success?
        status.zero?
      end
    end

    # Run a command, returning a Result. Never raises on a non-zero exit.
    def run(*args, input: nil)
      argv = args.map(&:to_s)
      stdout, stderr, status = Open3.capture3(*argv, stdin_data: input)
      Result.new(stdout, stderr, status.exitstatus || 1)
    end

    # Run a command, raising CommandError on a non-zero exit.
    def run!(*args, input: nil)
      result = run(*args, input: input)
      raise CommandError.new(args, result.status, result.stderr) unless result.success?

      result
    end

    # Run a command and return its stdout, raising on failure.
    def capture(*args, input: nil)
      run!(*args, input: input).stdout
    end

    # Resolve an executable on PATH, returning its path or nil.
    def which(command)
      result = run("sh", "-c", "command -v #{command}")
      result.success? ? result.stdout.strip : nil
    end
  end
end
