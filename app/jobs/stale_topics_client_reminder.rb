require 'action_view'
require 'active_support/core_ext/integer/inflections'

class StaleTopicsClientReminder
  include Sidekiq::Worker
  include ActionView::Helpers::DateHelper

  sidekiq_options :retry => false

  def perform(topic_id)
    topic = Topic.find_by(id: topic_id)
    staff_post = Post.find_by(id: topic.custom_fields["recent_staff_post"].to_i)
    op = User.find_by(id: topic.user_id.to_i)
    time_difference = distance_of_time_in_words_to_now(staff_post.created_at, scope: 'datetime.distance_in_words_verbose')
    url = "/t/#{topic_id}"

    # Send a message to the specified user
    post = PostCreator.create!(
      Discourse.system_user,
      target_usernames: op.username,
      archetype: Archetype.private_message,
      subtype: TopicSubtype.system_message,
      title: I18n.t("stale_topics_client_reminder.subject_template"),
      raw: I18n.t("stale_topics_client_reminder.text_body_template", username: op.username, base_url: Discourse.base_url, url: url, time_frame: time_difference),
      skip_validations: true
    )

    if SiteSetting.stale_topics_client_staff_whisper_reminder_enabled
      # Add a whisper to the post as well.
      post = PostCreator.create!(
        Discourse.system_user,
        topic_id: topic_id,
        post_type: Post.types[:whisper],
        raw: I18n.t("stale_topics_client_staff_whisper_reminder.text_body_template",group_name: SiteSetting.stale_topics_remind_staff_group, username: op.username,  time_frame: time_difference),
        whisper: true,
        skip_validations: true
      )
    end

    # If the reminder flag is still true, reinstantiate another worker instance.
    # Additionally update the worker to the retry interval instead of the default
    if topic.custom_fields["client_reminder_count"].to_i <= SiteSetting.stale_topics_max_client_replies.to_i
      duration = SiteSetting.stale_topics_retry_remind_client_duration
      units = SiteSetting.stale_topics_retry_remind_client_interval_units.to_sym
      ::StaleTopic.handle_client_reminder_job(topic, staff_post, ::StaleTopic::ReminderTask.reminder[:create_reminder], units, duration)
    end
  end
end
