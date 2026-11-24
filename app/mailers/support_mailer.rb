class SupportMailer < ApplicationMailer
  def ticket_received(feedback)
    @feedback = feedback
    @ticket_url = "https://soporte.libreria.org.pe/tickets/#{feedback.id}"
    mail(
      to: feedback.email,
      subject: "[Ticket ##{feedback.id}] #{strip_html(feedback.summary)}"
    )
  end

  def staff_replied(feedback, reply)
    @feedback = feedback
    @reply = reply
    @ticket_url = "https://soporte.libreria.org.pe/tickets/#{feedback.id}"
    mail(
      to: feedback.email,
      subject: "Re: [Ticket ##{feedback.id}] #{strip_html(feedback.summary)}"
    )
  end

  def new_ticket_alert(feedback)
    @feedback = feedback
    @admin_url = "https://libreria.org.pe/admin/support_tickets/#{feedback.id}"
    recipient = ArchiveConfig.ADMIN_ADDRESS.presence || "admin@libreria.org.pe"
    mail(
      to: recipient,
      subject: "[Soporte AO3] Nueva solicitud: #{strip_html(feedback.summary)} (#{feedback.username.presence || feedback.email})"
    )
  end

  def user_replied(feedback, reply)
    @feedback = feedback
    @reply = reply
    @admin_url = "https://libreria.org.pe/admin/support_tickets/#{feedback.id}"
    recipient = feedback.assigned_to&.email || ArchiveConfig.ADMIN_ADDRESS.presence || "admin@libreria.org.pe"
    mail(
      to: recipient,
      subject: "[Soporte AO3] Respuesta de usuario en Ticket ##{feedback.id}: #{strip_html(feedback.summary)}"
    )
  end

  private

  def strip_html(str)
    ActionController::Base.helpers.strip_tags(str.to_s).strip
  end
end
