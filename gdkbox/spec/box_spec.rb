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

  describe "#run_agent" do
    before { box.create! }

    it "runs claude headless in the GDK checkout, passing the task via env" do
      box.run_agent(task: "fix the failing spec")
      exec = shell.commands.find { |c| c[:argv].last.to_s.start_with?("claude -p") }
      expect(exec).not_to be_nil
      expect(exec[:argv]).to include("-u", "gdk", "-w", "/home/gdk/gdk")
      expect(exec[:argv]).to include("-e", "GDKBOX_TASK=fix the failing spec")
      expect(exec[:argv].last).to eq('claude -p "$GDKBOX_TASK" --dangerously-skip-permissions')
    end

    it "adds JSON output and a timeout when requested" do
      box.run_agent(task: "do it", json: true, timeout: 600)
      cmd = shell.commands.find { |c| c[:argv].last.to_s.include?("claude -p") }[:argv].last
      expect(cmd).to eq('timeout 600 claude -p "$GDKBOX_TASK" --output-format json --dangerously-skip-permissions')
    end

    it "omits the skip-permissions flag when yolo is disabled" do
      box.run_agent(task: "careful", yolo: false)
      cmd = shell.commands.find { |c| c[:argv].last.to_s.include?("claude -p") }[:argv].last
      expect(cmd).to eq('claude -p "$GDKBOX_TASK"')
    end

    it "returns the agent output and exit status without raising on failure" do
      failing = FakeShell.new(
        responses: {
          %(docker exec -i -u gdk -w /home/gdk/gdk -e GDKBOX_TASK=boom gdkbox-demo bash -lc claude -p "$GDKBOX_TASK" --dangerously-skip-permissions) =>
            GDKBox::Shell::Result.new("partial output", "agent error", 2)
        }
      )
      failed_box = described_class.new(
        "demo", config: config, shell: failing, store: store, ssh_key: ssh_key
      )
      result = failed_box.run_agent(task: "boom")
      expect(result.stdout).to eq("partial output")
      expect(result.status).to eq(2)
      expect(result).not_to be_success
    end
  end

  describe "#summary" do
    before { box.create! }

    it "produces a machine-readable descriptor for orchestrators" do
      summary = box.summary(state: "running")
      expect(summary).to include(
        "name" => "demo",
        "state" => "running",
        "ssh_host" => "gdkbox-demo",
        "ssh_port" => 2222,
        "web_url" => "http://127.0.0.1:3000",
        "remote_path" => "/home/gdk/gdk",
        "claude_installed" => true
      )
    end
  end
end
