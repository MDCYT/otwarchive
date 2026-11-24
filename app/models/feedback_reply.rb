class FeedbackReply < ApplicationRecord
  belongs_to :feedback
  belongs_to :user, optional: true
  belongs_to :admin, optional: true

  validates :comment, presence: true
  validates :author_name, presence: true

  scope :public_replies, -> { where(is_internal: false) }
  scope :internal_notes, -> { where(is_internal: true) }
  default_scope { order(created_at: :asc) }

  after_create :update_feedback_meta

  def staff?
    admin_id.present?
  end

  def update_sanitizer_version
    # FeedbackReply has no HTML sanitizer version columns in DB
  end

  private

  def update_feedback_meta
    feedback.update_columns(
      last_reply_at: created_at,
      last_reply_by: staff? ? 'staff' : 'user'
    )
  end
end
