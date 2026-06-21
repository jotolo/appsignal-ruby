# frozen_string_literal: true

RSpec.describe GDKBox::VSCode do
  let(:config) { build_config }
  let(:box) do
    GDKBox::Box.from_data(
      { "name" => "demo", "remote_path" => "/home/gdk/gdk" },
      config: config
    )
  end

  it "builds a Remote-SSH open command targeting the box host alias" do
    vscode = described_class.new(shell: FakeShell.new)
    expect(vscode.open_command(box)).to eq(
      ["code", "--remote", "ssh-remote+gdkbox-demo", "/home/gdk/gdk"]
    )
  end

  it "detects availability of the code CLI" do
    present = described_class.new(shell: FakeShell.new(which: { "code" => "/usr/bin/code" }))
    absent = described_class.new(shell: FakeShell.new(which: Hash.new(nil)))
    expect(present.available?).to be(true)
    expect(absent.available?).to be(false)
  end
end
