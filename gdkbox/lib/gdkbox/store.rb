# frozen_string_literal: true

require "json"

module GDKBox
  # Persists box metadata as one JSON file per box under the boxes directory.
  class Store
    def initialize(config:)
      @config = config
    end

    def path(name)
      File.join(@config.boxes_dir, "#{name}.json")
    end

    def exists?(name)
      File.exist?(path(name))
    end

    def save(box)
      @config.ensure_dirs!
      File.write(path(box["name"]), "#{JSON.pretty_generate(box)}\n")
      box
    end

    def load(name)
      return nil unless exists?(name)

      JSON.parse(File.read(path(name)))
    end

    def all
      Dir.glob(File.join(@config.boxes_dir, "*.json")).map do |file|
        JSON.parse(File.read(file))
      end
    end

    def delete(name)
      File.delete(path(name)) if exists?(name)
    end

    # Every host port already claimed by an existing box.
    def used_ports
      all.flat_map { |box| [box["ssh_port"], box["web_port"]] }.compact
    end
  end
end
