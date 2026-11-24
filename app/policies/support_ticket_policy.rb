class SupportTicketPolicy < ApplicationPolicy
  SUPPORT_ROLES = %w[superadmin support].freeze

  def index?
    user_has_roles?(SUPPORT_ROLES)
  end

  alias show? index?
  alias update? index?
  alias create? index?
  alias destroy? index?
  alias reply? index?
  alias update_status? index?
  alias assign? index?
end
