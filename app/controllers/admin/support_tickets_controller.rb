class Admin::SupportTicketsController < Admin::BaseController
  before_action :check_support_permission
  before_action :find_ticket, only: [:show, :reply, :update_status, :assign]

  def index
    @page_title = "Panel de Soporte - Solicitudes"
    @status_filter = params[:status].presence || "all"
    
    @counts = {
      all: Feedback.count,
      open: Feedback.where(status: "open").count,
      pending: Feedback.where(status: "pending").count,
      answered: Feedback.where(status: "answered").count,
      closed: Feedback.where(status: "closed").count
    }

    @tickets = case @status_filter
               when "open" then Feedback.where(status: "open")
               when "pending" then Feedback.where(status: "pending")
               when "answered" then Feedback.where(status: "answered")
               when "closed" then Feedback.where(status: "closed")
               else Feedback.all
               end

    @tickets = @tickets.order(updated_at: :desc).paginate(page: params[:page], per_page: 25)
  end

  def show
    @page_title = "Soporte: Ticket ##{@feedback.id} - #{@feedback.summary}"
    @replies = @feedback.feedback_replies
    @reply = FeedbackReply.new
    @admins = Admin.all
    @user = User.find_by(id: @feedback.user_id) || User.find_by(login: @feedback.username) || User.find_by(email: @feedback.email)
  end

  def reply
    comment_text = params[:feedback_reply]&.[](:comment)
    is_internal = params[:feedback_reply]&.[](:is_internal) == "1"

    if comment_text.blank?
      flash[:error] = "El mensaje no puede estar vacío."
      redirect_to admin_support_ticket_path(@feedback) and return
    end

    staff_name = "Soporte (#{current_admin.login})"
    @reply = @feedback.feedback_replies.create(
      admin_id: current_admin.id,
      author_name: staff_name,
      comment: comment_text,
      is_internal: is_internal
    )

    if @reply.persisted?
      unless is_internal
        new_status = params[:next_status].presence || "answered"
        @feedback.update(status: new_status)
        begin
          SupportMailer.staff_replied(@feedback, @reply).deliver_later
        rescue => e
          Rails.logger.error("Error sending staff reply email: #{e.message}")
        end
        flash[:notice] = "Respuesta enviada al usuario con éxito y notificada por correo."
      else
        flash[:notice] = "Nota interna guardada con éxito (no se envió correo al usuario)."
      end
    else
      flash[:error] = "No se pudo guardar la respuesta."
    end

    redirect_to admin_support_ticket_path(@feedback)
  end

  def update_status
    if Feedback::STATUSES.include?(params[:status])
      @feedback.update(status: params[:status])
      flash[:notice] = "Estado del ticket actualizado a '#{@feedback.status_label}'."
    else
      flash[:error] = "Estado no válido."
    end
    redirect_to admin_support_ticket_path(@feedback)
  end

  def assign
    admin = Admin.find_by(id: params[:admin_id])
    @feedback.update(assigned_to: admin)
    flash[:notice] = admin ? "Ticket asignado a #{admin.login}." : "Ticket desasignado."
    redirect_to admin_support_ticket_path(@feedback)
  end

  private

  def check_support_permission
    policy = SupportTicketPolicy.new(current_admin, Feedback)
    unless policy.index?
      flash[:error] = "No tienes permiso para acceder al panel de soporte."
      redirect_to admin_path and return
    end
  end

  def find_ticket
    @feedback = Feedback.find_by(id: params[:id])
    unless @feedback
      flash[:error] = "Ticket no encontrado."
      redirect_to admin_support_tickets_path and return
    end
  end
end
