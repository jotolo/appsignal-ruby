# frozen_string_literal: true

require "tmpdir"
require "fileutils"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "gdkbox"

# A test double for GDKBox::Shell that records every command instead of
# executing it. Canned responses can be supplied keyed by the joined argv.
class FakeShell
  Result = GDKBox::Shell::Result

  attr_reader :commands

  def initialize(responses: {}, which: nil)
    @commands = []
    @responses = responses
    @which = which || Hash.new { |_h, cmd| "/usr/bin/#{cmd}" }
  end

  def run(*args, input: nil)
    argv = args.map(&:to_s)
    @commands << { argv: argv, input: input }
    @responses.fetch(argv.join(" "), Result.new("", "", 0))
  end

  def run!(*args, input: nil)
    result = run(*args, input: input)
    raise GDKBox::CommandError.new(args, result.status, result.stderr) unless result.success?

    result
  end

  def capture(*args, input: nil)
    run!(*args, input: input).stdout
  end

  def which(command)
    @which[command]
  end

  # Every argv recorded, as a flat array of strings, for easy matching.
  def argvs
    @commands.map { |c| c[:argv] }
  end
end

module SpecHelpers
  def gdkbox_home
    @gdkbox_home
  end

  def build_config
    GDKBox::Config.new(home: gdkbox_home)
  end
end

RSpec.configure do |config|
  config.include SpecHelpers

  config.around do |example|
    Dir.mktmpdir do |dir|
      @gdkbox_home = File.join(dir, ".gdkbox")
      example.run
    end
  end
end
