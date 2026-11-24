# Class which holds feedback sent to the archive administrators about the archive as a whole
class Feedback < ApplicationRecord
  attr_accessor :ip_address, :referer, :site_skin

  has_many :feedback_replies, dependent: :destroy
  belongs_to :user, optional: true
  belongs_to :assigned_to, class_name: "Admin", foreign_key: "assigned_to_id", optional: true

  STATUSES = %w[open pending answered closed].freeze
  PRIORITIES = %w[low normal high urgent].freeze
  TICKET_TYPES = %w[technical abuse].freeze

  validates_presence_of :comment
  validates_presence_of :summary
  validates_presence_of :language
  validates :email, email_format: { allow_blank: false }
  validates_length_of :summary, maximum: ArchiveConfig.FEEDBACK_SUMMARY_MAX,
    too_long: ts("must be less than %{max} characters long.", max: ArchiveConfig.FEEDBACK_SUMMARY_MAX_DISPLAYED)

  validates :ticket_type, inclusion: { in: TICKET_TYPES }, allow_blank: true
  validates :reported_url, presence: true, if: :abuse?, length: { maximum: 2080 }

  before_validation :truncate_reported_url, if: :will_save_change_to_reported_url?

  def truncate_reported_url
    self.reported_url = reported_url[0..2079] if reported_url.present?
  end

  validate :check_for_spam

  scope :by_status, ->(s) { where(status: s) if s.present? && STATUSES.include?(s) }
  scope :by_type, ->(t) { where(ticket_type: t) if t.present? && TICKET_TYPES.include?(t) }
  scope :recent, -> { order(updated_at: :desc) }

  def abuse?
    ticket_type == "abuse"
  end

  def technical?
    !abuse?
  end

  def type_label
    abuse? ? "Policy & Abuse" : "Technical Support"
  end

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def answered?
    status == "answered"
  end

  def pending?
    status == "pending"
  end

  def status_label
    case status
    when "open" then I18n.t("support_tickets.status.open", default: "Open")
    when "pending" then I18n.t("support_tickets.status.pending", default: "Pending")
    when "answered" then I18n.t("support_tickets.status.answered", default: "Answered")
    when "closed" then I18n.t("support_tickets.status.closed", default: "Closed")
    else status.to_s.humanize
    end
  end

  def priority_label
    case priority
    when "low" then I18n.t("support_tickets.priority.low", default: "Low")
    when "normal" then I18n.t("support_tickets.priority.normal", default: "Normal")
    when "high" then I18n.t("support_tickets.priority.high", default: "High")
    when "urgent" then I18n.t("support_tickets.priority.urgent", default: "Urgent")
    else priority.to_s.humanize
    end
  end

  def check_for_spam
    # Don't check for spam if the user is logged in with matching email
    return if logged_in_with_matching_email?

    # Don't check for spam unless Akismet is configured
    return unless AkismetClient.enabled?

    if AkismetClient.spam?(akismet_attributes)
      errors.add(:base, ts("This message looks like spam to our system! If you are human, please try again or contact an admin directly."))
    end
  end

  def logged_in_with_matching_email?
    User.current_user.present? && User.current_user.email.downcase == email.to_s.downcase
  end

  def akismet_attributes
    name = username.presence || ""
    {
      comment_author: name,
      comment_author_email: email,
      comment_content: "#{summary}

#{comment}",
      user_ip: ip_address,
      user_agent: user_agent,
      referrer: referer
    }
  end

  def email_and_send
    SupportMailer.ticket_received(self).deliver_later rescue nil
  end

  def rollout_string
    return "" unless rollout.present?
    rollout
  end
end
