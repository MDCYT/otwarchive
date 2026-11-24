class Users::SessionsController < Devise::SessionsController

  layout "session"
  before_action :admin_logout_required, except: [:destroy]

  # POST /users/login
  def create
    super do |resource|
      unless resource.remember_me
        message = ts(" <strong>You'll stay logged in for %{number} weeks even if you close your browser, so make sure to log out if you're using a public or shared computer.</strong>", number: ArchiveConfig.DEFAULT_SESSION_LENGTH_IN_WEEKS)
      end
      flash[:notice] += message unless message.nil?
      flash[:notice] = flash[:notice].html_safe
    end
  end

  # GET /users/logout
  def confirm_logout
    # If the user confirmed via GET (e.g. from query param or direct click) or already logged out
    if params[:confirm] == "true"
      destroy and return
    end

    redirect_to root_path unless user_signed_in?
  end

  include PathCleaner
  # DELETE /users/logout
  def destroy
    clear_user_session_and_cookies
    set_flash_message! :notice, :signed_out
    redirect_to relative_path(params[:return_to]) || root_path
  end

  private

  def clear_user_session_and_cookies
    if current_user
      current_user.forget_me! rescue nil
    end

    domains = [nil, :all, ".#{ArchiveConfig.APP_HOST}", ArchiveConfig.APP_HOST].compact.uniq
    domains.each do |dom|
      opts = dom == :all ? { domain: :all } : (dom ? { domain: dom } : {})
      cookies.delete(:remember_user_token, **opts)
      cookies.delete("remember_user_token", **opts)
      cookies.delete(:user_credentials, **opts)
      cookies.delete("user_credentials", **opts)
      cookies.delete(:_otwarchive_session, **opts)
      cookies.delete("_otwarchive_session", **opts)
    end

    sign_out(:user) rescue nil
    warden.logout(:user) rescue nil
    reset_session
  end
end
