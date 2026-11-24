class SupportController < ApplicationController
  def index
    @page_title = "Centro de Ayuda y Soporte"
    @open_tickets_count = current_user ? Feedback.where(user_id: current_user.id, status: %w[open pending answered]).count : 0
  end

  def faq
    @page_title = "Preguntas Frecuentes - Soporte"
    @faqs = ArchiveFaq.default_order rescue []
  end
end
