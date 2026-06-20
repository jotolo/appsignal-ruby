# frozen_string_literal: true

RSpec.describe GDKBox::Box do
  let(:config) { build_config }
  let(:shell) { FakeShell.new }
  let(:store) { GDKBox::Store.new(config: config) }
  let(:ssh_key) do
    instance_double(
      GDKBox::SSHKey,
      ensure!: "ssh-ed25519 AAAAKEY gdkbox",
      public_key: "ssh-ed25519 AAAAKEY gdkbox"
    )
  end

  subject(:box) do
    described_class.new("demo", config: config, shell: shell, store: store, ssh_key: ssh_key)
  end

  describe "#create!" do
    it "pulls, runs, provisions and persists metadata" do
      data = box.create!

      expect(data).to include(
        "name" => "demo",
        "container_name" => "gdkbox-demo",
        "ssh_port" => 2222,
        "web_port" => 3000,
        "ssh_user" => "gdk",
        "claude_installed" => true
      )
      expect(store.exists?("demo")).to be(true)

      flat = shell.argvs.map { |a| a.join(" ") }
      expect(flat).to include(a_string_starting_with("docker pull"))
      expect(flat).to include(a_string_starting_with("docker run -d --name gdkbox-demo"))
      ssh_exec = shell.commands.find { |c| c[:argv].include?("bash") && c[:argv].last.include?("sshd") }
      expect(ssh_exec).not_to be_nil
      expect(ssh_exec[:argv]).to include("-e", "GDKBOX_PUBKEY=ssh-ed25519 AAAAKEY gdkbox")
    end

    it "publishes the SSH and web ports to localhost" do
      box.create!
      run_cmd = shell.commands.find { |c| c[:argv][0, 2] == %w[docker run] }
      expect(run_cmd[:argv]).to include("-p", "127.0.0.1:2222:22")
      expect(run_cmd[:argv]).to include("-p", "127.0.0.1:3000:3000")
    end

    it "skips Claude Code installation when requested" do
      box.create!(install_claude: false)
      claude = shell.commands.find { |c| c[:argv].last.to_s.include?("claude-code") }
      expect(claude).to be_nil
      expect(store.load("demo")["claude_installed"]).to be(false)
    end

    it "allocates the next free ports around existing boxes" do
      store.save("name" => "existing", "ssh_port" => 2222, "web_port" => 3000)
      data = box.create!
      expect(data["ssh_port"]).to eq(2223)
      expect(data["web_port"]).to eq(3001)
    end

    it "refuses to clobber an existing box" do
      box.create!
      expect { box.create! }.to raise_error(GDKBox::Error, /already exists/)
    end
  end

  describe "lifecycle" do
    before { box.create! }

    it "re-enables ssh on start" do
      shell.commands.clear
      box.start!
      flat = shell.argvs.map { |a| a.join(" ") }
      expect(flat).to include("docker start gdkbox-demo")
      expect(shell.commands.any? { |c| c[:argv].last.to_s.include?("sshd") }).to be(true)
    end

    it "stops the container" do
      shell.commands.clear
      box.stop!
      expect(shell.argvs).to include(%w[docker stop gdkbox-demo])
    end

    it "removes container and metadata on destroy" do
      box.destroy!
      expect(shell.argvs).to include(%w[docker rm -f gdkbox-demo])
      expect(store.exists?("demo")).to be(false)
    end

    it "records Claude installation" do
      store.save(store.load("demo").merge("claude_installed" => false))
      reloaded = described_class.new(
        "demo", config: config, shell: shell, store: store, ssh_key: ssh_key
      )
      reloaded.install_claude!
      expect(store.load("demo")["claude_installed"]).to be(true)
    end
  end

  describe "connection helpers" do
    before { box.create! }

    it "exposes ssh + web + vscode details" do
      expect(box.ssh_host_alias).to eq("gdkbox-demo")
      expect(box.ssh_command).to eq(%w[ssh gdkbox-demo])
      expect(box.web_url).to eq("http://127.0.0.1:3000")
      expect(box.remote_path).to eq("/home/gdk/gdk")
    end
  end
end
