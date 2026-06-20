# frozen_string_literal: true

require_relative "lib/gdkbox/version"

Gem::Specification.new do |spec|
  spec.name = "gdkbox"
  spec.version = GDKBox::VERSION
  spec.authors = ["AppSignal"]
  spec.summary = "Spin up a GitLab Development Kit (GDK) in a box, ready for VS Code and Claude Code."
  spec.description = <<~DESC
    gdkbox is a small CLI that spins up GitLab's official "GDK in a box" image
    in a Docker container, enables SSH access for VS Code Remote-SSH, and
    installs Claude Code inside the box so you can run agents against a real
    GitLab development environment.
  DESC
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir[
    "lib/**/*.rb",
    "exe/*",
    "README.md"
  ]
  spec.bindir = "exe"
  spec.executables = ["gdkbox"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", ">= 1.0", "< 2.0"

  spec.add_development_dependency "rspec", "~> 3.0"
end
