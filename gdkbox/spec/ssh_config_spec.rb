# frozen_string_literal: true

RSpec.describe GDKBox::SSHConfig do
  let(:config) { build_config }
  let(:user_config_path) { File.join(gdkbox_home, "user_ssh_config") }

  subject(:ssh_config) { described_class.new(config: config) }

  before do
    allow(config).to receive(:user_ssh_config).and_return(user_config_path)
  end

  let(:boxes) do
    [
      { "name" => "beta", "ssh_port" => 2223, "web_port" => 3001, "ssh_user" => "gdk" },
      { "name" => "alpha", "ssh_port" => 2222, "web_port" => 3000, "ssh_user" => "gdk" }
    ]
  end

  it "renders one sorted Host block per box" do
    rendered = ssh_config.render(boxes)
    expect(rendered).to include("Host gdkbox-alpha")
    expect(rendered).to include("Host gdkbox-beta")
    expect(rendered.index("gdkbox-alpha")).to be < rendered.index("gdkbox-beta")
    expect(rendered).to include("Port 2222")
    expect(rendered).to include("User gdk")
    expect(rendered).to include("IdentityFile #{config.private_key_path}")
  end

  it "writes the fragment and adds an Include to the user ssh config" do
    ssh_config.write(boxes)
    expect(File.read(config.ssh_config_path)).to include("Host gdkbox-alpha")
    expect(File.read(user_config_path)).to include("Include #{config.ssh_config_path}")
  end

  it "does not duplicate the Include directive" do
    ssh_config.write(boxes)
    ssh_config.write(boxes)
    contents = File.read(user_config_path)
    expect(contents.scan("Include #{config.ssh_config_path}").length).to eq(1)
  end
end
