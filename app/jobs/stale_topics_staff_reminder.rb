class StaleTopicsStaffReminder
  include Sidekiq::Worker
  sidekiq_options :retry => false

  def perform(topic_id)
    #TODO: Update worker
  end
end
