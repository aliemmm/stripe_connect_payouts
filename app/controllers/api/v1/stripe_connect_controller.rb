class Api::V1:::StripeConnectController < Api::V1::ApiController
  before_action :authorize_user
  before_action :check_user_stripe_account, except: [:connect]

  def connect
    unless current_user.stripe_connect_id.present?
      account = create_stripe_account_for_user
      if account
        current_user.update(stripe_connect_id: account.id)
      else
        return render json: { error: "Unable to create Stripe account" }, status: :unprocessable_entity
      end
    end

    link = create_account_link(current_user.stripe_connect_id)
    render json: { user: current_user, link: link.url }
  end

  def balance_check
    balance = retrieve_stripe_balance(current_user.stripe_connect_id)
    if balance
      render json: {
        balance: balance['available'][0]['amount'] / 100,
        currency: balance['available'][0]['currency']
      }
    else
      render json: { error: "Unable to retrieve balance" }, status: :unprocessable_entity
    end
  end

  def login_link
    link = Stripe::Account.create_login_link(current_user.stripe_connect_id)
    render json: { link: link.url }
  rescue Stripe::InvalidRequestError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def retrieve
    account = Stripe::Account.retrieve(current_user.stripe_connect_id)
    render json: { account: account }
  rescue Stripe::InvalidRequestError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def check_user_stripe_account
    if current_user.stripe_connect_id.nil?
      render json: { message: "Please create a Stripe account first" }, status: :unauthorized
    end
  end

  def create_stripe_account_for_user
    Stripe::Account.create(
      type: "express",
      email: current_user.email,
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true }
      },
      business_type: "individual",
      individual: {
        email: current_user.email
      }
    )
  rescue Stripe::InvalidRequestError => e
    Rails.logger.error("Stripe Account Creation Error: #{e.message}")
    nil
  end

  def create_account_link(stripe_connect_id)
    Stripe::AccountLink.create(
      account: stripe_connect_id,
      refresh_url: api_v1_users_stripe_connect_connect_url,
      return_url: "https://textng.page.link/qL6j",
      type: "account_onboarding"
    )
  rescue Stripe::InvalidRequestError => e
    Rails.logger.error("Stripe Account Link Creation Error: #{e.message}")
    nil
  end

  def retrieve_stripe_balance(stripe_connect_id)
    Stripe::Balance.retrieve({ stripe_account: stripe_connect_id })
  rescue Stripe::InvalidRequestError => e
    Rails.logger.error("Stripe Balance Retrieval Error: #{e.message}")
    nil
  end
end
