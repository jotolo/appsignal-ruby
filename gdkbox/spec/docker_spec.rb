# frozen_string_literal: true

RSpec.describe GDKBox::Docker do
  let(:shell) { FakeShell.new }
  subject(:docker) { described_class.new(shell: shell) }

  it "builds a run command with ports, labels and env" do
    docker.run_container(
      name: "gdkbox-demo",
      image: "img:tag",
      publish: ["127.0.0.1:2222:22"],
      labels: { "gdkbox" => "true", "gdkbox.name" => "demo" },
      env: { "FOO" => "bar" }
    )

    argv = shell.argvs.last
    expect(argv).to include("docker", "run", "-d", "--name", "gdkbox-demo", "img:tag")
    expect(argv).to include("-p", "127.0.0.1:2222:22")
    expect(argv).to include("--label", "gdkbox=true")
    expect(argv).to include("-e", "FOO=bar")
  end

  it "runs exec scripts through bash -lc with the given user and env" do
    docker.exec("gdkbox-demo", "echo hi", user: "root", env: { "K" => "v" })
    argv = shell.argvs.last
    expect(argv).to eq(
      ["docker", "exec", "-i", "-u", "root", "-e", "K=v", "gdkbox-demo", "bash", "-lc", "echo hi"]
    )
  end

  it "reports container state, returning :absent on failure" do
    shell = FakeShell.new(
      responses: {
        "docker inspect -f {{.State.Status}} present" =>
          GDKBox::Shell::Result.new("running\n", "", 0),
        "docker inspect -f {{.State.Status}} missing" =>
          GDKBox::Shell::Result.new("", "no such object", 1)
      }
    )
    docker = described_class.new(shell: shell)
    expect(docker.state("present")).to eq(:running)
    expect(docker.state("missing")).to eq(:absent)
  end

  it "lists box names from container labels" do
    shell = FakeShell.new(
      responses: {
        %(docker ps -a --filter label=gdkbox=true --format {{index .Labels "gdkbox.name"}}) =>
          GDKBox::Shell::Result.new("demo\nother\n", "", 0)
      }
    )
    expect(described_class.new(shell: shell).list_names).to eq(%w[demo other])
  end
end
