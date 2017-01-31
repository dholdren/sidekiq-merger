require "spec_helper"

describe Sidekiq::Merger::Redis do
  subject { described_class.new }
  let(:now) { Time.now }
  let(:execution_time) { now + 10.seconds }
  before { Timecop.freeze(now) }

  describe ".purge" do
    it "cleans up all the keys" do
      described_class.redis do |conn|
        conn.sadd("sidekiq-merger:merges", "test")
        conn.set("sidekiq-merger:unique_msg:foo", "test")
        conn.set("sidekiq-merger:msg:foo", "test")
        conn.set("sidekiq-merger:lock:foo", "test")
      end

      described_class.purge!

      described_class.redis do |conn|
        expect(conn.smembers("sidekiq-merger:merges")).to be_empty
        expect(conn.keys("sidekiq-merger:unique_msg:*")).to be_empty
        expect(conn.keys("sidekiq-merger:msg:*")).to be_empty
        expect(conn.keys("sidekiq-merger:lock:*")).to be_empty
      end
    end
  end

  describe "#push" do
    shared_examples_for "push spec" do
      it "pushes the args" do
        subject.push(pushing_key, pushing_msg, pushing_execution_time)
        described_class.redis do |conn|
          expect(conn.smembers("sidekiq-merger:merges")).to contain_exactly(*merge_keys)
          expect(conn.keys("sidekiq-merger:time:*")).to contain_exactly(*times.keys)
          expect(conn.keys("sidekiq-merger:unique_msg:*")).to contain_exactly(*unique_msgs_h.keys)
          unique_msgs_h.each do |key, msgs|
            expect(conn.smembers(key)).to contain_exactly(*msgs)
          end
          expect(conn.keys("sidekiq-merger:msg:*")).to contain_exactly(*msgs_h.keys)
          msgs_h.each do |key, msgs|
            expect(conn.lrange(key, 0, -1)).to contain_exactly(*msgs)
          end
        end
      end
      it "sets the execution time" do
        subject.push(pushing_key, pushing_msg, pushing_execution_time)
        described_class.redis do |conn|
          merge_keys.each do |key, time|
            expect(conn.get(key)).to eq time
          end
        end
      end
    end

    let(:pushing_key) { "foo" }
    let(:pushing_msg) { [1, 2, 3] }
    let(:pushing_execution_time) { execution_time }

    include_examples "push spec" do
      let(:merge_keys) { ["foo"] }
      let(:times) { {
        "sidekiq-merger:time:foo" => execution_time.to_i.to_s,
      } }
      let(:unique_msgs_h) { {
        "sidekiq-merger:unique_msg:foo" => ["[1,2,3]"]
      } }
      let(:msgs_h) { {
        "sidekiq-merger:msg:foo" => ["[1,2,3]"]
      } }
    end

    context "the merge key already exists" do
      let(:pushing_msg) { [2, 3, 4] }
      before { subject.push("foo", [1, 2, 3], execution_time) }
      include_examples "push spec" do
        let(:merge_keys) { ["foo"] }
        let(:times) { {
          "sidekiq-merger:time:foo" => execution_time.to_i.to_s,
        } }
        let(:unique_msgs_h) { {
          "sidekiq-merger:unique_msg:foo" => ["[1,2,3]", "[2,3,4]"]
        } }
        let(:msgs_h) { {
          "sidekiq-merger:msg:foo" => ["[1,2,3]", "[2,3,4]"]
        } }
      end
    end

    context "the args has already ben pushed" do
      before { subject.push("foo", [1, 2, 3], execution_time) }
      include_examples "push spec" do
        let(:merge_keys) { ["foo"] }
        let(:times) { {
          "sidekiq-merger:time:foo" => execution_time.to_i.to_s,
        } }
        let(:unique_msgs_h) { {
          "sidekiq-merger:unique_msg:foo" => ["[1,2,3]"]
        } }
        let(:msgs_h) { {
          "sidekiq-merger:msg:foo" => ["[1,2,3]", "[1,2,3]"]
        } }
      end
    end

    context "other merge key already exists" do
      let(:pushing_key) { "bar" }
      let(:pushing_msg) { [2, 3, 4] }
      let(:pushing_execution_time) { execution_time + 1.hour }
      before { subject.push("foo", [1, 2, 3], execution_time) }
      include_examples "push spec" do
        let(:merge_keys) { ["foo", "bar"] }
        let(:times) { {
          "sidekiq-merger:time:foo" => execution_time.to_i.to_s,
          "sidekiq-merger:time:bar" => (execution_time + 1.hour).to_i.to_s,
        } }
        let(:unique_msgs_h) { {
          "sidekiq-merger:unique_msg:foo" => ["[1,2,3]"],
          "sidekiq-merger:unique_msg:bar" => ["[2,3,4]"],
        } }
        let(:msgs_h) { {
          "sidekiq-merger:msg:foo" => ["[1,2,3]"],
          "sidekiq-merger:msg:bar" => ["[2,3,4]"],
        } }
      end
    end
  end

  describe "#delete" do
  end

  describe "#merge_size" do
  end

  describe "#exists?" do
    context "unique key exists" do
      it "returns true" do
        described_class.redis { |conn| conn.sadd("sidekiq-merger:unique_msg:foo", "\"test\"") }
        expect(subject.exists?("foo", "test")).to eq true
      end
    end
    context "unique key does not exists" do
      it "returns false" do
        expect(subject.exists?("foo", "test")).to eq false
      end
    end
  end

  describe "#all" do
  end

  describe "#lock" do
  end

  describe "#get" do
  end

  describe "#pluck" do
    before do
      subject.push("bar", [1, 2, 3], execution_time)
      subject.push("bar", [2, 3, 4], execution_time)
    end
    it "plucks all the args" do
      expect(subject.pluck("bar")).to contain_exactly [1, 2, 3], [2, 3, 4]
    end
  end

  describe "#delete_all" do
  end
end
