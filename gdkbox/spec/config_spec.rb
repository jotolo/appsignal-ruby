# frozen_string_literal: true

RSpec.describe GDKBox::Config do
  subject(:config) { build_config }

  it "derives all paths under the home directory" do
    expect(config.boxes_dir).to eq(File.join(gdkbox_home, "boxes"))
    expect(config.keys_dir).to eq(File.join(gdkbox_home, "keys"))
    expect(config.ssh_config_path).to eq(File.join(gdkbox_home, "ssh_config"))
    expect(config.public_key_path).to end_with("id_ed25519.pub")
  end

  it "honours the GDKBOX_HOME environment variable" do
    custom = File.join(gdkbox_home, "custom")
    with_env("GDKBOX_HOME" => custom) do
      expect(GDKBox::Config.new.home).to eq(File.expand_path(custom))
    end
  end

  it "names containers and ssh hosts consistently" do
    expect(config.container_name("demo")).to eq("gdkbox-demo")
    expect(config.ssh_host_alias("demo")).to eq("gdkbox-demo")
  end

  it "defaults to the official GDK image but allows an override" do
    expect(config.default_image).to eq(GDKBox::Config::DEFAULT_IMAGE)
    with_env("GDKBOX_IMAGE" => "example/image:tag") do
      expect(config.default_image).to eq("example/image:tag")
    end
  end

  def with_env(vars)
    previous = vars.transform_values { |_| nil }
    vars.each { |k, v| previous[k] = ENV[k]; ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| ENV[k] = v }
  end
end
