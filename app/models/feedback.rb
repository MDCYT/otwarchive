# Class which holds feedback sent to the archive administrators about the archive as a whole
class Feedback < ApplicationRecord
  attr_accessor :ip_address, :referer, :site_skin

  has_many :feedback_replies, dependent: :destroy
  belongs_to :user, optional: true
  belongs_to :assigned_to, class_name: "Admin", foreign_key: "assigned_to_id", optional: true

  STATUSES = %w[open pending answered closed].freeze
  PRIORITIES = %w[low normal high urgent].freeze

  validates_presence_of :comment
  validates_presence_of :summary
  validates_presence_of :language
  validates :email, email_format: { allow_blank: false }
  validates_length_of :summary, maximum: ArchiveConfig.FEEDBACK_SUMMARY_MAX,
    too_long: ts("must be less than %{max} characters long.", max: ArchiveConfig.FEEDBACK_SUMMARY_MAX_DISPLAYED)

  validate :check_for_spam

  scope :by_status, ->(s) { where(status: s) if s.present? && STATUSES.include?(s) }
  scope :recent, -> { order(updated_at: :desc) }

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
    when "open" then "Abierto"
    when "pending" then "En espera"
    when "answered" then "Respondido"
    when "closed" then "Resuelto"
    else (status || "Abierto").titleize
    end
  end

  def check_for_spam
    approved = logged_in_with_matching_email? || !AkismetClient.spam?(akismet_attributes)
    errors.add(:base, ts("This report looks like spam to our system!")) unless approved
  end

  def logged_in_with_matching_email?
    User.current_user.present? && User.current_user.email == email
  end

  def akismet_attributes
    role = User.current_user.present? ? "user-with-nonmatching-email" : "guest"
    {
      comment_type: "contact-form",
      user_ip: ip_address,
      user_agent: user_agent,
      user_role: role,
      comment_author_email: email,
      comment_content: comment
    }
  end

  def mark_as_spam!
    AkismetClient.submit_spam(akismet_attributes)
  end

  def mark_as_ham!
    AkismetClient.submit_ham(akismet_attributes)
  end

  def email_and_send
    UserMailer.feedback(id).deliver_later
    begin
      SupportMailer.new_ticket_alert(self).deliver_later
    rescue => e
      Rails.logger.error("Support notification alert failed: #{e.message}")
    end
    send_report
  end

  def rollout_string
    ""
  end

  def send_report
    return unless zoho_enabled?

    reporter = SupportReporter.new(
      title: summary,
      description: comment,
      language: language,
      email: email,
      username: username,
      user_agent: user_agent,
      site_revision: ArchiveConfig.REVISION.to_s,
      rollout: rollout,
      ip_address: ip_address,
      referer: referer,
      site_skin: site_skin
    )
    reporter.send_report!
  end

  private

  def zoho_enabled?
    %w[staging production].include?(Rails.env)
  end
end
