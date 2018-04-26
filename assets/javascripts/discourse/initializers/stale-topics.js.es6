import { withPluginApi } from "discourse/lib/plugin-api";

function appendSidekiqLink(api) {
  api.onPageChange((url, title) => {
    if(url.indexOf("filter=stale_topics") > -1) {
      var sidekiqURL = Discourse.BaseUrl + "/sidekiq/scheduled"
      $('.admin-detail').append('<span style="width: 17.6576%; margin-right: 12px; float: left; margin-left: .5rem;">Load Sidekiq:</span> <button id="sidekiq-url" tabindex="5" aria-label="Or press Ctrl+Enter" title="Or press Ctrl+Enter" class="btn btn-icon-text btn-primary create ember-view">  <i class="fa fa-sign-in d-icon d-icon-sign-in"></i><span class="d-button-label">Open Sidekiq<!----></span></button>');
      $('#sidekiq-url').on('click', () => {
        window.location.href = "/sidekiq"
      })
    }
  })
}

export default {
  name: "stale-topics",
  initialize(container) {
    if(Discourse.SiteSettings.stale_topics_show_sidekiq) {
      withPluginApi("0.8", appendSidekiqLink)
    }
  }
}
