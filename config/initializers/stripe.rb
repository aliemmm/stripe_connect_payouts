Rails.configuration.stripe = {
  :secret_key => ENV["SECRET_KEY"],
  :publishable_key => ENV["PUBLISHABLE_KEY"]
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]