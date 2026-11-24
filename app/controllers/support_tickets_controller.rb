class SupportTicketsController < ApplicationController
  before_action :find_ticket, only: [:show, :reply, :close]
  before_action :authorize_ticket_access, only: [:show, :reply, :close]

  def index
    @page_title = t("support_tickets.index.page_title")
    if current_user
      @tickets = Feedback.where("user_id = ? OR email = ? OR username = ?", current_user.id, current_user.email, current_user.login)
                         .order(updated_at: :desc)
    elsif session[:recent_ticket_ids].present?
      @tickets = Feedback.where(id: session[:recent_ticket_ids]).order(updated_at: :desc)
    else
      @tickets = Feedback.none
    end
  end

  def new
    @page_title = t("feedbacks.new.heading.page_title")
    @admin_setting = AdminSetting.default
    @support_languages = Language.where(support_available: true).default_order rescue Language.all
    @support_languages = Language.all if @support_languages.blank?
    @support_notice = SupportNotice.current_notice rescue nil
    @feedback = Feedback.new
    @feedback.username = current_user.login if current_user
    @feedback.email = current_user.email if current_user
    @feedback.language = Language.default&.name || "English"
    @open_tickets_count = current_user ? Feedback.where(user_id: current_user.id, status: %w[open pending answered]).count : 0
  end

  def create
    @feedback = Feedback.new(ticket_params)
    @feedback.user_id = current_user&.id
    @feedback.status = "open"
    @feedback.priority = "normal"
    @feedback.user_agent = request.env["HTTP_USER_AGENT"]&.to(499)
    @feedback.ip_address = request.remote_ip
    @feedback.site_skin = helpers.current_skin

    if @feedback.save
      session[:recent_ticket_ids] ||= []
      session[:recent_ticket_ids] << @feedback.id

      begin
        SupportMailer.ticket_received(@feedback).deliver_later
        SupportMailer.new_ticket_alert(@feedback).deliver_later
      rescue => e
        Rails.logger.error("Error sending support emails: #{e.message}")
      end

      flash[:notice] = t("support_tickets.flash.created", id: @feedback.id)
      redirect_to ticket_path(@feedback)
    else
      @admin_setting = AdminSetting.default
      @support_languages = Language.where(support_available: true).default_order rescue Language.all
      @support_languages = Language.all if @support_languages.blank?
      @support_notice = SupportNotice.current_notice rescue nil
      @open_tickets_count = current_user ? Feedback.where(user_id: current_user.id, status: %w[open pending answered]).count : 0
      flash[:error] = t("support_tickets.flash.create_error")
      render :new
    end
  end

  def show
    @page_title = t("support_tickets.show.ticket_title", id: @feedback.id, summary: @feedback.summary)
    @replies = @feedback.feedback_replies.public_replies
    @reply = FeedbackReply.new
  end

  def reply
    comment_text = params[:feedback_reply]&.[](:comment)
    if comment_text.blank?
      flash[:error] = t("support_tickets.flash.reply_empty")
      redirect_to ticket_path(@feedback) and return
    end

    author = current_user ? current_user.login : (@feedback.username.presence || @feedback.email)
    @reply = @feedback.feedback_replies.create(
      user_id: current_user&.id,
      author_name: author,
      comment: comment_text,
      is_internal: false
    )

    if @reply.persisted?
      @feedback.update(status: "pending") if @feedback.answered? || @feedback.closed?
      begin
        SupportMailer.user_replied(@feedback, @reply).deliver_later
      rescue => e
        Rails.logger.error("Error sending user reply notification: #{e.message}")
      end
      flash[:notice] = t("support_tickets.flash.reply_success")
    else
      flash[:error] = t("support_tickets.flash.reply_error")
    end
    redirect_to ticket_path(@feedback)
  end

  def close
    @feedback.update(status: "closed")
    flash[:notice] = t("support_tickets.flash.closed", id: @feedback.id)
    redirect_to ticket_path(@feedback)
  end

  private

  def ticket_params
    params.require(:feedback).permit(:summary, :comment, :category, :email, :username, :language)
  end

  def find_ticket
    @feedback = Feedback.find_by(id: params[:id])
    unless @feedback
      flash[:error] = t("support_tickets.flash.not_found")
      redirect_to tickets_path and return
    end
  end

  def authorize_ticket_access
    return true if logged_in_as_admin?
    if current_user
      return true if @feedback.user_id == current_user.id ||
                     @feedback.email == current_user.email ||
                     @feedback.username == current_user.login
    end
    if session[:recent_ticket_ids]&.include?(@feedback.id)
      return true
    end
    if params[:email].present? && @feedback.email.downcase == params[:email].strip.downcase
      session[:recent_ticket_ids] ||= []
      session[:recent_ticket_ids] << @feedback.id
      return true
    end

    flash[:error] = t("support_tickets.flash.access_denied")
    redirect_to tickets_path
  end
end
