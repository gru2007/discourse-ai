# frozen_string_literal: true

RSpec.describe DiscourseAi::Completions::Prompt do
  subject(:prompt) { described_class.new(system_insts) }

  let(:system_insts) { "These are the system instructions." }
  let(:user_msg) { "Write something nice" }
  let(:username) { "username1" }
  let(:image100x100) { plugin_file_from_fixtures("100x100.jpg") }

  describe ".new" do
    it "raises for invalid attributes" do
      expect { described_class.new("a bot", messages: {}) }.to raise_error(ArgumentError)
      expect { described_class.new("a bot", tools: {}) }.to raise_error(ArgumentError)

      bad_messages = [{ type: :user, content: "a system message", unknown_attribute: :random }]
      expect { described_class.new("a bot", messages: bad_messages) }.to raise_error(ArgumentError)

      bad_messages2 = [{ type: :user }]
      expect { described_class.new("a bot", messages: bad_messages2) }.to raise_error(ArgumentError)

      bad_messages3 = [{ content: "some content associated to no one" }]
      expect { described_class.new("a bot", messages: bad_messages3) }.to raise_error(ArgumentError)
    end
  end

  describe "image support" do
    it "allows adding uploads to messages" do
      upload = UploadCreator.new(image100x100, "image.jpg").create_for(Discourse.system_user.id)

      prompt.max_pixels = 300
      prompt.push(type: :user, content: "hello", upload_ids: [upload.id])

      expect(prompt.messages.last[:upload_ids]).to eq([upload.id])
      expect(prompt.max_pixels).to eq(300)

      encoded = prompt.encoded_uploads(prompt.messages.last)

      expect(encoded.length).to eq(1)
      expect(encoded[0][:mime_type]).to eq("image/jpeg")

      old_base64 = encoded[0][:base64]

      prompt.max_pixels = 1_000_000

      encoded = prompt.encoded_uploads(prompt.messages.last)

      expect(encoded.length).to eq(1)
      expect(encoded[0][:mime_type]).to eq("image/jpeg")

      new_base64 = encoded[0][:base64]

      expect(new_base64.length).to be > old_base64.length
      expect(new_base64.length).to be > 0
      expect(old_base64.length).to be > 0
    end
  end

  describe "#push" do
    describe "turn validations" do
      it "validates that tool messages have a previous tool_call message" do
        prompt.push(type: :user, content: user_msg, id: username)
        prompt.push(type: :model, content: "I'm a model msg")

        expect { prompt.push(type: :tool, content: "I'm the tool call results") }.to raise_error(
          DiscourseAi::Completions::Prompt::INVALID_TURN,
        )
      end

      it "validates that model messages have either a previous tool or user messages" do
        prompt.push(type: :user, content: user_msg, id: username)
        prompt.push(type: :model, content: "I'm a model msg")

        expect { prompt.push(type: :model, content: "I'm a second model msg") }.to raise_error(
          DiscourseAi::Completions::Prompt::INVALID_TURN,
        )
      end
    end

    it "system message is always first" do
      prompt.push(type: :user, content: user_msg, id: username)

      system_message = prompt.messages.first

      expect(system_message[:type]).to eq(:system)
      expect(system_message[:content]).to eq(system_insts)
    end

    it "includes the pushed message" do
      prompt.push(type: :user, content: user_msg, id: username)

      system_message = prompt.messages.last

      expect(system_message[:type]).to eq(:user)
      expect(system_message[:content]).to eq(user_msg)
      expect(system_message[:id]).to eq(username)
    end
  end
end
