# name: stale-topics
# about: Ensure stale topics are followed-up on
# version: 0.1
# authors: Jordan Seanor
# url: https://github.com/HMSAB/discourse-stale-topics.git
require_relative 'app/jobs/stale_topics_staff_reminder.rb'
require_relative 'app/jobs/stale_topics_client_reminder.rb'

enabled_site_setting :stale_topics_enabled

after_initialize do

  # When a topic/post is created if the staff reminder site setting is enabled
  # create a sidekiq task to remind the users at the defined interval.
  #
  # Topic is updated with:
  # staff_reminder_job_id INT - Thintervale sidekiq task id so we can cancel later
  # staff_reminder_needs BOOLEAN - Denotes if the topic required staff response
  DiscourseEvent.on(:post_created) do |post, opts, user|
    if SiteSetting.stale_topics_enabled
      topic = Topic.find_by(id: post.topic_id)
      if SiteSetting.stale_topics_remind_staff && SiteSetting.stale_topics_remind_staff_duration > 0 && !is_excluded_user(user)
        ::StaleTopic.handle_client_reminder_job(topic, post, ::StaleTopic::ReminderTask.reminder[:remove_reminder], nil, 0)
        duration = SiteSetting.stale_topics_remind_staff_duration
        units = SiteSetting.stale_topics_remind_staff_interval_units.to_sym
        ::StaleTopic.handle_staff_reminder_job(topic, ::StaleTopic::ReminderTask.reminder[:create_reminder], units, duration)
      else
        if topic.posts_count.to_i != 1
          ::StaleTopic.handle_staff_reminder_job(topic, ::StaleTopic::ReminderTask.reminder[:remove_reminder], nil, 0)
          duration = SiteSetting.stale_topics_retry_remind_client_duration
          units = SiteSetting.stale_topics_retry_remind_client_interval_units.to_sym
          ::StaleTopic.handle_client_reminder_job(topic, post, ::StaleTopic::ReminderTask.reminder[:create_reminder], units, duration)
        end
      end
    end
  end

  def is_excluded_user(user)
    user.admin || user.moderator || (return false if user.id < 0) # don't wanna flag system posts
  end

  class ::StaleTopic

    # Create or cancel a scheduled staff reminder task
    # Additionally update the topic to clear out any
    # custom fields. If the defined member replies, clear out the task.
    def self.handle_staff_reminder_job(topic, remind, units, duration)
      if remind
        topic.custom_fields["staff_reminder_count"] = topic.custom_fields["staff_reminder_count"].to_i + 1
        topic.custom_fields["staff_needs_reminder"] = true
        staff_reminder_id = StaleTopicsStaffReminder.perform_in(::StaleTopic.create_reminder_datetime(units, duration), topic.id)
        if !staff_reminder_id.nil?
          topic.custom_fields["staff_reminder_job_id"] = staff_reminder_id
          topic.save!
        end
      else
        staff_reminder_id = topic.custom_fields["staff_reminder_job_id"]
        scheduled = Sidekiq::ScheduledSet.new
        scheduled.each do |job|
          if job.klass == 'StaleTopicsStaffReminder' && job.jid == staff_reminder_id
            job.delete
          end
        end
        topic.custom_fields["staff_needs_reminder"] = false
        topic.custom_fields["staff_reminder_job_id"] = nil
        topic.custom_fields["staff_reminder_count"] = 0
        topic.save!
      end
    end

    def self.handle_client_reminder_job(topic, post, remind, units, duration)
      if remind
        topic.custom_fields["client_reminder_count"] = topic.custom_fields["client_reminder_count"].to_i + 1
        if post.user_id > 0
          topic.custom_fields["recent_staff_post"] = post.id
        end
        if topic.custom_fields["client_reminder_count"].to_i <= SiteSetting.stale_topics_max_client_replies.to_i
          scheduled = Sidekiq::ScheduledSet.new
          scheduled.each do |job|
            if job.args[0].is_a?(Integer)
              if job.klass == 'StaleTopicsClientReminder' && job.args[0].to_i == topic.id
                job.delete
              end
            end
          end
          client_reminder_id = StaleTopicsClientReminder.perform_in(::StaleTopic.create_reminder_datetime(units, duration), topic.id)
          if !client_reminder_id.nil?
            topic.custom_fields["client_reminder_job_id"] = client_reminder_id
            topic.save!
          end
        end
      else
        client_reminder_id = topic.custom_fields["client_reminder_job_id"]
        scheduled = Sidekiq::ScheduledSet.new
        scheduled.each do |job|
          if job.klass == 'StaleTopicsClientReminder' && job.jid == client_reminder_id
            job.delete
          end
        end
        topic.custom_fields["client_reminder_job_id"] = nil
        topic.custom_fields["client_reminder_count"] = 0
        topic.save!
      end
    end

    # Dynamically create timespan from plugin sitesettings
    def self.create_reminder_datetime(units, duration)
      case(units)
      when :minutes
        return duration.minutes
      when :hours
        return duration.hours
      when :days
        return duration.days
      when :months
        return duration.months
      else
        return 24.hours
      end
    end

    module ReminderTask
      def self.reminder
        @entries ||= Enum.new(
          create_reminder: true,
          remove_reminder: false
        )
      end
    end
  end
end
