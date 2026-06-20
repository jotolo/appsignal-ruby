# frozen_string_literal: true

RSpec.describe GDKBox::Store do
  subject(:store) { described_class.new(config: build_config) }

  let(:box) do
    { "name" => "demo", "ssh_port" => 2222, "web_port" => 3000 }
  end

  it "saves and loads a box round-trip" do
    store.save(box)
    expect(store.exists?("demo")).to be(true)
    expect(store.load("demo")).to eq(box)
  end

  it "returns nil for an unknown box" do
    expect(store.load("nope")).to be_nil
    expect(store.exists?("nope")).to be(false)
  end

  it "lists all boxes" do
    store.save(box)
    store.save(box.merge("name" => "other"))
    expect(store.all.map { |b| b["name"] }).to contain_exactly("demo", "other")
  end

  it "collects every used port across boxes" do
    store.save(box)
    store.save("name" => "other", "ssh_port" => 2223, "web_port" => 3001)
    expect(store.used_ports).to contain_exactly(2222, 3000, 2223, 3001)
  end

  it "deletes a box" do
    store.save(box)
    store.delete("demo")
    expect(store.exists?("demo")).to be(false)
  end
end
