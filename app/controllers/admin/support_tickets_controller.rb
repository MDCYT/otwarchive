class Admin::SupportTicketsController < Admin::BaseController
  before_action :admin_only
  before_action :find_ticket, only: [:show, :reply, :update_status, :assign]

  def index
    @page_title = t("admin.support_tickets.index.page_title", default: "Support Tickets Dashboard")
    @status_filter = params[:status].presence || "all"
    @type_filter = params[:type].presence || "all"

    base_scope = Feedback.all
    if @type_filter != "all" && Feedback::TICKET_TYPES.include?(@type_filter)
      base_scope = base_scope.where(ticket_type: @type_filter)
    end

    @tickets = base_scope.order(updated_at: :desc)
    if @status_filter != "all" && Feedback::STATUSES.include?(@status_filter)
      @tickets = @tickets.where(status: @status_filter)
    end

    @counts = {
      all: base_scope.count,
      open: base_scope.where(status: "open").count,
      pending: base_scope.where(status: "pending").count,
      answered: base_scope.where(status: "answered").count,
      closed: base_scope.where(status: "closed").count,
      technical: Feedback.where(ticket_type: [nil, "technical"]).count,
      abuse: Feedback.where(ticket_type: "abuse").count
    }
  end

  def show
    @page_title = "[Ticket ##{@feedback.id}] #{@feedback.summary}"
    @replies = @feedback.feedback_replies
    @reply = FeedbackReply.new
    @user = @feedback.user || (@feedback.username.present? ? User.find_by(login: @feedback.username) : nil) || (@feedback.email.present? ? User.find_by(email: @feedback.email) : nil)
    @admins = Admin.all.order(:login)
  end

  def reply
    comment_text = params[:feedback_reply]&.[](:comment)&.strip
    is_internal = params[:feedback_reply]&.[](:is_internal) == "1"

    if comment_text.blank?
      flash[:error] = t("support_tickets.flash.reply_empty", default: "Response cannot be blank.")
      redirect_to admin_support_ticket_path(@feedback) and return
    end

    # Duplicate prevention: if the exact same reply was submitted within 2 minutes, ignore and redirect
    recent_dup = @feedback.feedback_replies
      .where(admin_id: current_admin.id, comment: comment_text)
      .where("created_at > ?", 2.minutes.ago)
      .first
    if recent_dup
      flash[:notice] = t("admin.support_tickets.flash.reply_success", default: "Reply sent to user.")
      redirect_to admin_support_ticket_path(@feedback) and return
    end

    staff_name = "Support (#{current_admin.login})"
    @reply = @feedback.feedback_replies.create(
      admin_id: current_admin.id,
      author_name: staff_name,
      comment: comment_text,
      is_internal: is_internal
    )

    if @reply.persisted?
      unless is_internal
        new_status = params[:next_status].presence || "answered"
        @feedback.update_columns(status: new_status) if Feedback::STATUSES.include?(new_status)
        begin
          SupportMailer.staff_replied(@feedback, @reply).deliver_later
        rescue => e
          Rails.logger.error("Error sending staff reply email: #{e.message}")
        end
        flash[:notice] = t("admin.support_tickets.flash.reply_success", default: "Reply sent to user.")
      else
        flash[:notice] = t("admin.support_tickets.flash.note_success", default: "Internal note added.")
      end
    else
      flash[:error] = t("support_tickets.flash.reply_error", default: "Could not post reply.")
    end

    redirect_to admin_support_ticket_path(@feedback)
  end

  def update_status
    if Feedback::STATUSES.include?(params[:status])
      @feedback.update(status: params[:status])
      flash[:notice] = t("admin.support_tickets.flash.status_updated", status: @feedback.status_label, default: "Status updated to %{status}.")
    end
    redirect_to admin_support_ticket_path(@feedback)
  end

  def assign
    admin_id = params[:admin_id].presence
    if admin_id == "unassign"
      @feedback.update(assigned_to_id: nil)
      flash[:notice] = t("admin.support_tickets.flash.unassigned", default: "Ticket unassigned.")
    elsif admin_id.present? && (admin = Admin.find_by(id: admin_id))
      @feedback.update(assigned_to_id: admin.id)
      flash[:notice] = t("admin.support_tickets.flash.assigned", admin: admin.login, default: "Ticket assigned to %{admin}.")
    end
    redirect_to admin_support_ticket_path(@feedback)
  end

  private

  def find_ticket
    @feedback = Feedback.find_by(id: params[:id])
    unless @feedback
      flash[:error] = t("support_tickets.flash.not_found", default: "Ticket not found.")
      redirect_to admin_support_tickets_path and return
    end
  end
end
