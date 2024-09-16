class Api::V1::CheckoutController < Api::V1::ApiController
  before_action :check_card_or_bank, only: [:create_charge_for_theme, :create_charge_for_burn_number]
  before_action :authorize_user

  def create_charge_for_theme
    @type = "Theme"
    theme = Theme.find_by(id: params[:theme_id])
    return render json: { message: "Please provide a valid theme ID!" }, status: :unauthorized unless theme

    return render json: { message: "User has already bought this theme!" }, status: :unauthorized if UserTheme.exists?(user_id: current_user.id, theme_id: params[:theme_id])

    charge = process_stripe_charge(theme.price, "Theme charged successfully!")
    return render json: { message: charge[:error] }, status: :unprocessable_entity if charge[:error]

    payment = create_payment(theme.id, theme.price)
    user_theme = UserTheme.create(user_id: current_user.id, theme_id: theme.id)
    
    if user_theme
      render json: { message: "Theme purchased successfully!", charge: charge, payment: payment }
    else
      render json: { message: "Failed to purchase theme!" }, status: :unprocessable_entity
    end
  end

  def create_charge_for_burn_number
    @type = "BurnNumber"
    return render json: { message: "This number is already assigned!" }, status: :unauthorized if current_user.textng_number == params[:new_number]
    return render json: { message: "This number has already been burned!" }, status: :unauthorized if BurnNumber.exists?(burn_number: current_user.textng_number)

    charge = process_stripe_charge(params[:price], "Burn Number charged successfully!")
    return render json: { message: charge[:error] }, status: :unprocessable_entity if charge[:error]

    create_burn_number(charge)
    notify_user("TextNg Number Purchased", "TextNg Number has been purchased successfully.")
  end

  def apple_pay_theme
    process_apple_or_google_pay(:apple, "Theme")
  end

  def apple_pay_burn_number
    process_apple_or_google_pay(:apple, "BurnNumber")
  end

  def google_pay_theme
    process_apple_or_google_pay(:google, "Theme")
  end

  def google_pay_burn_number
    process_apple_or_google_pay(:google, "BurnNumber")
  end

  private

  def check_card_or_bank
    @source, @source_type = find_payment_source
    return render json: { message: "Invalid source provided!" }, status: :unauthorized unless @source
  end

  def find_payment_source
    if params[:card_id].present?
      card = current_user.cards.find_by(id: params[:card_id])
      return [card.token, "Credit Card"] if card
    elsif params[:bank_id].present?
      bank = current_user.banks.find_by(id: params[:bank_id])
      return [bank.token, "Bank"] if bank
    elsif current_user.stripe_connect_id.present?
      return [current_user.stripe_connect_id, "Connect"]
    end
    [nil, nil]
  end

  def process_stripe_charge(amount, description)
    amount_in_cents = (amount.to_f * 100).to_i
    begin
      Stripe::Charge.create({
        amount: amount_in_cents,
        currency: "usd",
        customer: current_user.stripe_customer_id,
        source: @source,
        description: description,
      })
    rescue Stripe::CardError => e
      { error: e.message }
    end
  end

  def create_payment(payment_on_id, amount)
    Payment.create(
      user_id: current_user.id,
      payment_on_id: payment_on_id,
      payment_on_type: @type,
      amount: amount.to_i,
      source_type: @source_type
    )
  end

  def create_burn_number(charge)
    ActiveRecord::Base.transaction do
      burn_number = BurnNumber.create!(burn_number: current_user.textng_number, user_id: current_user.id)
      current_user.update!(textng_number: params[:new_number], textng_number_created_at: DateTime.now)
      burn_number.update!(bought_last: current_user.textng_number_created_at)

      payment = create_payment(burn_number.id, params[:price])
      render json: { charge: charge, payment: payment }
    rescue ActiveRecord::RecordInvalid => e
      render json: { message: "Error during burn number creation: #{e.message}" }, status: :unprocessable_entity
    end
  end

  def process_apple_or_google_pay(platform, type)
    @type = type
    item_id = type == "Theme" ? params[:theme_id] : params[:new_number]
    item = type == "Theme" ? Theme.find_by(id: item_id) : BurnNumber.find_by(burn_number: current_user.textng_number)

    return render json: { message: "#{type} not found!" }, status: :not_found unless item
    return render json: { message: "#{type} has already been purchased!" }, status: :unauthorized if already_purchased?(type, item_id)

    begin
      intent = Stripe::PaymentIntent.create({
        amount: (item.price.to_f * 100).to_i,
        currency: "usd"
      })
    rescue Stripe::CardError => e
      return render json: { message: e.message }, status: :unprocessable_entity
    end

    payment = create_payment(item.id, item.price)
    notify_user("Success Purchased", "#{type} has been successfully purchased.")
    render json: { message: "#{type} purchased successfully!", intent: intent, payment: payment }
  end

  def already_purchased?(type, item_id)
    if type == "Theme"
      UserTheme.exists?(user_id: current_user.id, theme_id: item_id)
    elsif type == "BurnNumber"
      BurnNumber.exists?(burn_number: current_user.textng_number)
    else
      false
    end
  end

  def notify_user(title, description)
    current_user.notifications.create(
      title: title,
      descrption: description,
      notification_date: Time.now
    )
  end
end
