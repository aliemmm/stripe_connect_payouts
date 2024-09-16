class ApiController < ActionController::API
  helper_method :current_user

  protected

  def authorize_user
    return render json: { message: "Invalid token" } unless request.headers["Authorization"]

    token = request.headers["Authorization"].split(" ").last
    user = User.find_by(api_key: token)

    return render json: { message: "Invalid token" } unless user
  end

  def current_user
    if request.headers["Authorization"].present?
      token = request.headers["Authorization"].split(" ").last
    end
    current_user ||= user = User.find_by(api_key: token)
  end

  def param_clean(_params)
    _params.delete_if do |k, v|
      if v.instance_of?(ActionController::Parameters)
        param_clean(v)
      end
      v.empty?
    end
  end
end
