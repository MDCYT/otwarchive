class Admin::SupportTicketsController < Admin::BaseController
  before_action :check_support_permission
  before_action :find_ticket, only: [:show, :reply, :update_status, :assign]

  def index
    @page_title = t("admin.support_tickets.index.page_title")
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
    @page_title = t("admin.support_tickets.show.page_title", id: @feedback.id, summary: @feedback.summary)
    @replies = @feedback.feedback_replies
    @reply = FeedbackReply.new
    @admins = Admin.all
    @user = User.find_by(id: @feedback.user_id) || User.find_by(login: @feedback.username) || User.find_by(email: @feedback.email)
  end

  def reply
    comment_text = params[:feedback_reply]&.[](:comment)
    is_internal = params[:feedback_reply]&.[](:is_internal) == "1"

    if comment_text.blank?
      flash[:error] = t("support_tickets.flash.reply_empty")
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
        @feedback.update(status: new_status)
        begin
          SupportMailer.staff_replied(@feedback, @reply).deliver_later
        rescue => e
          Rails.logger.error("Error sending staff reply email: #{e.message}")
        end
        flash[:notice] = t("admin.support_tickets.flash.reply_success")
      else
        flash[:notice] = t("admin.support_tickets.flash.note_success")
      end
    else
      flash[:error] = t("support_tickets.flash.reply_error")
    end

    redirect_to admin_support_ticket_path(@feedback)
  end

  def update_status
    if Feedback::STATUSES.include?(params[:status])
      @feedback.update(status: params[:status])
      flash[:notice] = t("admin.support_tickets.flash.status_updated", status: @feedback.status_label)
    else
      flash[:error] = t("admin.support_tickets.flash.invalid_status")
    end
    redirect_to admin_support_ticket_path(@feedback)
  end

  def assign
    admin = Admin.find_by(id: params[:admin_id])
    @feedback.update(assigned_to: admin)
    flash[:notice] = admin ? t("admin.support_tickets.flash.assigned", admin: admin.login) : t("admin.support_tickets.flash.unassigned")
    redirect_to admin_support_ticket_path(@feedback)
  end

  private

  def check_support_permission
    policy = SupportTicketPolicy.new(current_admin, Feedback)
    unless policy.index?
      flash[:error] = t("admin.support_tickets.flash.permission_denied")
      redirect_to admin_path and return
    end
  end

  def find_ticket
    @feedback = Feedback.find_by(id: params[:id])
    unless @feedback
      flash[:error] = t("support_tickets.flash.not_found")
      redirect_to admin_support_tickets_path and return
    end
  end
end
