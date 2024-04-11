# frozen_string_literal: true

require_relative "dialect_context"

RSpec.describe DiscourseAi::Completions::Dialects::Llama2Classic do
  let(:model_name) { "Llama2-chat-hf" }
  let(:context) { DialectContext.new(described_class, model_name) }

  describe "#translate" do
    it "translates a prompt written in our generic format to the Llama2 format" do
      llama2_classic_version = <<~TEXT
      [INST]
      <<SYS>>
      #{context.system_insts}
      #{described_class.tool_preamble(include_array_tip: false)}
      <tools>
      #{context.dialect_tools}</tools>
      <</SYS>>
      [/INST]
      [INST]#{context.simple_user_input}[/INST]
      TEXT

      translated = context.system_user_scenario

      expect(translated).to eq(llama2_classic_version)
    end

    it "translates tool messages" do
      expected = +(<<~TEXT)
      [INST]
      <<SYS>>
      #{context.system_insts}
      #{described_class.tool_preamble(include_array_tip: false)}
      <tools>
      #{context.dialect_tools}</tools>
      <</SYS>>
      [/INST]
      [INST]This is a message by a user[/INST]
      I'm a previous bot reply, that's why there's no user
      [INST]This is a new message by a user[/INST]
      [INST]
      <function_results>
      <result>
      <tool_name>tool_id</tool_name>
      <json>
      "I'm a tool result"
      </json>
      </result>
      </function_results>
      [/INST]
      TEXT

      expect(context.multi_turn_scenario).to eq(expected)
    end

    it "trims content if it's getting too long" do
      translated = context.long_user_input_scenario

      expect(translated.length).to be < context.long_message_text.length
    end
  end
end
