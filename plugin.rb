# name: stale-topics
# about: Ensure stale topics are followed-up on
# version: 0.1
# authors: Jordan Seanor
# url:
require_relative 'app/jobs/stale_topics_staff_reminder.rb'

enabled_site_setting :stale_topics_enabled

after_initialize do

  Topic.register_custom_field_type('staff_reminder_job_id', :int)
  Topic.register_custom_field_type('staff_needs_reminder', :boolean)
  add_to_serializer(:topic_view, :custom_fields, false){object.topic.custom_fields}

  # When a topic is created if the staff reminder site setting is enabled
  # create a sidekiq task to remind the users at the defined interval.
  #
  # Topic is updated with:
  # staff_reminder_job_id INT - Thintervale sidekiq task id so we can cancel later
  # staff_reminder_needs BOOLEAN - Denotes if the topic required staff response
  DiscourseEvent.on(:topic_created) do |topic|
    poster = User.find_by(id: topic.user_id)
    if SiteSetting.stale_topics_remind_staff && SiteSetting.stale_topics_remind_staff_duration > 0 && !is_excluded_user(poster)
      StaleTopic.handle_staff_reminder_job(topic, true)
    end
  end

  def is_excluded_user(user)
    user.admin || user.moderator
  end

  class StaleTopic

    # Create or cancel a scheduled staff reminder task
    # Additionally update the topic to clear out any
    # custom fields
    def self.handle_staff_reminder_job(topic, remind)
      if remind
        topic.custom_fields["staff_needs_reminder"] = true
        duration = SiteSetting.stale_topics_remind_staff_duration
        units = SiteSetting.stale_topics_remind_staff_interval_units.to_sym
        staff_reminder_id = StaleTopicsStaffReminder.perform_in(StaleTopic.create_reminder_datetime(units, duration), topic.id)
        if !staff_reminder_id.nil?
          topic.custom_fields["staff_reminder_job_id"] = staff_reminder_id
          topic.save!
        end
      else
        staff_reminder_id = topic.custom_fields["staff_needs_reminder"]
        Sidekiq::Status.cancel staff_reminder_id
        topic.custom_fields["staff_needs_reminder"] = false
        topic.custom_fields["staff_reminder_job_id"] = nil
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
  end
end
