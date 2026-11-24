class SupportTicketsController < ApplicationController
  before_action :find_ticket, only: [:show, :reply, :close]
  before_action :authorize_ticket_access, only: [:show, :reply, :close]

  def index
    @page_title = t("support_tickets.index.page_title", default: "My Support Requests")
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
    @ticket_type = params[:type] == "abuse" ? "abuse" : "technical"
    @page_title = @ticket_type == "abuse" ? t("abuse_reports.new.heading.page_title", default: "Policy Questions & Abuse Reports") : t("feedbacks.new.heading.page_title", default: "Technical Support & Feedback")
    @admin_setting = AdminSetting.default
    @support_languages = Language.where(support_available: true).default_order rescue Language.all
    @support_languages = Language.all if @support_languages.blank?
    @abuse_languages = Language.where(abuse_support_available: true).default_order rescue Language.all
    @abuse_languages = @support_languages if @abuse_languages.blank?
    @support_notice = SupportNotice.current_notice rescue nil

    @feedback = Feedback.new(ticket_type: @ticket_type)
    @feedback.reported_url = params[:url] || request.referer if @ticket_type == "abuse"
    @feedback.username = current_user.login if current_user
    @feedback.email = current_user.email if current_user
    @feedback.language = Language.default&.name || "English"
    @open_tickets_count = current_user ? Feedback.where(user_id: current_user.id, status: %w[open pending answered]).count : 0
  end

  def create
    @feedback = Feedback.new(ticket_params)
    @ticket_type = @feedback.ticket_type == "abuse" ? "abuse" : "technical"
    @feedback.ticket_type = @ticket_type
    @feedback.user_id = current_user&.id
    @feedback.status = "open"
    @feedback.priority = (@ticket_type == "abuse" ? "high" : "normal")
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

      flash[:notice] = t("support_tickets.flash.created", id: @feedback.id, default: "Your ticket #%{id} has been received. Our team will review it shortly.")
      redirect_to ticket_path(@feedback)
    else
      @admin_setting = AdminSetting.default
      @support_languages = Language.where(support_available: true).default_order rescue Language.all
      @support_languages = Language.all if @support_languages.blank?
      @abuse_languages = Language.where(abuse_support_available: true).default_order rescue Language.all
      @abuse_languages = @support_languages if @abuse_languages.blank?
      @support_notice = SupportNotice.current_notice rescue nil
      @open_tickets_count = current_user ? Feedback.where(user_id: current_user.id, status: %w[open pending answered]).count : 0
      @page_title = @ticket_type == "abuse" ? t("abuse_reports.new.heading.page_title", default: "Policy Questions & Abuse Reports") : t("feedbacks.new.heading.page_title", default: "Technical Support & Feedback")
      flash[:error] = t("support_tickets.flash.create_error", default: "Could not submit your ticket. Please review the errors below.")
      render :new
    end
  end

  def show
    @page_title = t("support_tickets.show.ticket_title", id: @feedback.id, summary: @feedback.summary, default: "Ticket #%{id}: %{summary}")
    @replies = @feedback.feedback_replies.public_replies
    @reply = FeedbackReply.new
  end

  def reply
    comment_text = params[:feedback_reply]&.[](:comment)&.strip
    if comment_text.blank?
      flash[:error] = t("support_tickets.flash.reply_empty", default: "Response cannot be blank.")
      redirect_to ticket_path(@feedback) and return
    end

    author = current_user ? current_user.login : (@feedback.username.presence || @feedback.email)

    # Duplicate prevention
    recent_dup = @feedback.feedback_replies
      .where(author_name: author, comment: comment_text)
      .where("created_at > ?", 2.minutes.ago)
      .first
    if recent_dup
      flash[:notice] = t("support_tickets.flash.reply_success", default: "Your reply has been posted.")
      redirect_to ticket_path(@feedback) and return
    end

    @reply = @feedback.feedback_replies.create(
      user_id: current_user&.id,
      author_name: author,
      comment: comment_text,
      is_internal: false
    )

    if @reply.persisted?
      @feedback.update_columns(status: "pending") if @feedback.answered? || @feedback.closed?
      flash[:notice] = t("support_tickets.flash.reply_success", default: "Your reply has been posted.")
    else
      flash[:error] = t("support_tickets.flash.reply_error", default: "Could not send your reply. Please try again.")
    end

    redirect_to ticket_path(@feedback)
  end

  def close
    @feedback.update(status: "closed")
    flash[:notice] = t("support_tickets.flash.closed", id: @feedback.id, default: "Ticket #%{id} has been marked as closed.")
    redirect_to ticket_path(@feedback)
  end

  private

  def find_ticket
    @feedback = Feedback.find_by(id: params[:id])
    unless @feedback
      flash[:error] = t("support_tickets.flash.not_found", default: "Ticket not found.")
      redirect_to tickets_path and return
    end
  end

  def authorize_ticket_access
    return if logged_in_as_admin?
    if current_user
      return if @feedback.user_id == current_user.id
      return if @feedback.email.present? && @feedback.email.downcase == current_user.email.downcase
      return if @feedback.username.present? && @feedback.username.downcase == current_user.login.downcase
    end
    if session[:recent_ticket_ids]&.include?(@feedback.id)
      return
    end

    flash[:error] = t("support_tickets.flash.unauthorized", default: "You do not have permission to view this ticket.")
    redirect_to tickets_path
  end

  def ticket_params
    params.require(:feedback).permit(
      :username, :email, :summary, :comment, :category, :language, :ticket_type, :reported_url
    )
  end
end
