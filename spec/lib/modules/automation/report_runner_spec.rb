# frozen_string_literal: true

require "rails_helper"

module DiscourseAi
  module Automation
    describe ReportRunner do
      fab!(:user)
      fab!(:receiver) { Fabricate(:user) }
      fab!(:post) { Fabricate(:post, user: user) }
      fab!(:group)
      fab!(:secure_category) { Fabricate(:private_category, group: group) }
      fab!(:secure_topic) { Fabricate(:topic, category: secure_category) }
      fab!(:secure_post) { Fabricate(:post, raw: "Top secret date !!!!", topic: secure_topic) }

      fab!(:category)
      fab!(:topic_in_category) { Fabricate(:topic, category: category) }
      fab!(:post_in_category) do
        Fabricate(:post, raw: "I am in a category", topic: topic_in_category)
      end

      fab!(:tag)
      fab!(:topic_with_tag) { Fabricate(:topic, tags: [tag]) }
      fab!(:post_with_tag) { Fabricate(:post, raw: "I am in a tag", topic: topic_with_tag) }

      describe "#run!" do
        it "is able to generate email reports" do
          freeze_time

          DiscourseAi::Completions::Llm.with_prepared_responses(["magical report"]) do
            ReportRunner.run!(
              sender_username: user.username,
              receivers: ["fake@discourse.com"],
              title: "test report %DATE%",
              model: "gpt-4",
              category_ids: nil,
              tags: nil,
              allow_secure_categories: false,
              sample_size: 100,
              instructions: "make a magic report",
              days: 7,
              offset: 0,
              priority_group_id: nil,
              tokens_per_post: 150,
              debug_mode: nil,
            )
          end

          expect(ActionMailer::Base.deliveries.length).to eq(1)
          expect(ActionMailer::Base.deliveries.first.subject).to eq(
            "test report #{7.days.ago.strftime("%Y-%m-%d")} - #{Time.zone.now.strftime("%Y-%m-%d")}",
          )
        end

        it "can exclude categories" do
          freeze_time

          DiscourseAi::Completions::Llm.with_prepared_responses(["magical report"]) do
            ReportRunner.run!(
              sender_username: user.username,
              receivers: [receiver.username],
              title: "test report",
              model: "gpt-4",
              category_ids: nil,
              tags: nil,
              allow_secure_categories: false,
              debug_mode: true,
              sample_size: 100,
              instructions: "make a magic report",
              days: 7,
              offset: 0,
              priority_group_id: nil,
              tokens_per_post: 150,
              exclude_category_ids: [category.id],
            )
          end

          report = Topic.where(title: "test report").first
          debugging = report.ordered_posts.last.raw

          expect(debugging).not_to include(post_in_category.raw)
        end

        it "can suppress notifications by remapping content" do
          markdown = <<~MD
            @sam is a person
            [test1](/test) is an internal link
            [test2](/test?1=2) is an internal link
            [test3](https://example.com) is an external link
            [test4](#{Discourse.base_url}) is an internal link
            <a href='/test'>test5</a> is an internal link
            [test6](/test?test=test#anchor) is an internal link with fragment
            [test7](//[[test) is a link with an invalid URL
          MD

          DiscourseAi::Completions::Llm.with_prepared_responses([markdown]) do
            ReportRunner.run!(
              sender_username: user.username,
              receivers: [receiver.username],
              title: "test report",
              model: "gpt-4",
              category_ids: nil,
              tags: nil,
              allow_secure_categories: false,
              debug_mode: false,
              sample_size: 100,
              instructions: "make a magic report",
              days: 7,
              offset: 0,
              priority_group_id: nil,
              tokens_per_post: 150,
              suppress_notifications: true,
            )
          end

          report = Topic.where(title: "test report").first

          # note, magic surprise &amp; is correct HTML 5 representation
          expected = <<~HTML
            <p><a href="/u/sam" class="mention">@sam</a> is a person<br>
            <a href="/test?silent=true">test1</a> is an internal link<br>
            <a href="/test?1=2&amp;silent=true">test2</a> is an internal link<br>
            <a href="https://example.com" rel="noopener nofollow ugc">test3</a> is an external link<br>
            <a href="http://test.localhost?silent=true">test4</a> is an internal link<br>
            <a href="/test?silent=true">test5</a> is an internal link<br>
            <a href="/test?test=test&amp;silent=true#anchor">test6</a> is an internal link with fragment<br>
            <a href="//%5B%5Btest?silent=true" rel="noopener nofollow ugc">test7</a> is a link with an invalid URL</p>
          HTML

          expect(report.ordered_posts.first.raw.strip).to eq(expected.strip)
        end

        it "can exclude tags" do
          freeze_time

          DiscourseAi::Completions::Llm.with_prepared_responses(["magical report"]) do
            ReportRunner.run!(
              sender_username: user.username,
              receivers: [receiver.username],
              title: "test report",
              model: "gpt-4",
              category_ids: nil,
              tags: nil,
              allow_secure_categories: false,
              debug_mode: true,
              sample_size: 100,
              instructions: "make a magic report",
              days: 7,
              offset: 0,
              priority_group_id: nil,
              tokens_per_post: 150,
              exclude_tags: [tag.name],
            )
          end

          report = Topic.where(title: "test report").first
          debugging = report.ordered_posts.last.raw

          expect(debugging).to include(post_in_category.raw)
          expect(debugging).not_to include(post_with_tag.raw)
        end

        it "generates correctly respects the params" do
          DiscourseAi::Completions::Llm.with_prepared_responses(["magical report"]) do
            ReportRunner.run!(
              sender_username: user.username,
              receivers: [receiver.username],
              title: "test report",
              model: "gpt-4",
              category_ids: nil,
              tags: nil,
              allow_secure_categories: false,
              debug_mode: true,
              sample_size: 100,
              instructions: "make a magic report",
              days: 7,
              offset: 0,
              priority_group_id: nil,
              tokens_per_post: 150,
            )
          end

          report = Topic.where(title: "test report").first
          expect(report.ordered_posts.first.raw).to eq("magical report")
          debugging = report.ordered_posts.last.raw

          expect(debugging).to include(post.raw)
          expect(debugging).to include(post_in_category.raw)
          expect(debugging).to include(post_with_tag.raw)
          expect(debugging).not_to include(secure_post.raw)
        end
      end
    end
  end
end
