class SupportController < ApplicationController
  def index
    @page_title = t("support.home.page_title")
    @open_tickets_count = current_user ? Feedback.where(user_id: current_user.id, status: %w[open pending answered]).count : 0
  end

  def faq
    @page_title = t("support.faq.page_title")
    @faqs = ArchiveFaq.default_order rescue []
  end
end
