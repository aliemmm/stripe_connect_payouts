class Api::V1::TransactionsController < Api::V1::ApiController
  before_action :authorize_user
  before_action :check_stripe_connect_account, except: [:transaction_history]

  def topup
    @type = "TopUp"
    card = current_user.cards.find_by(id: params[:card_id])
    return render json: { message: "Card not present" }, status: :unauthorized unless card.present?

    amount_in_cents = amount_to_cents(params[:amount])
    charge, transfer = process_topup(card, amount_in_cents)

    if charge && transfer
      balance = retrieve_stripe_balance
      topup = create_transaction("TopUp", charge.amount / 100, "Credit Card")
      if topup.save
        render json: build_response("Top up Successful", charge, balance, card)
      else
        render json: { message: "Top up Not Successful" }, status: :unauthorized
      end
    end
  rescue => e
    render json: { message: e.message }, status: :unauthorized
  end

  def transfer
    @type = "Transfer"
    return render json: { message: "Insufficient Funds" } unless sufficient_funds?(params[:amount])

    receiver = current_user.contacts.find_by(id: params[:receiver_id])
    return render json: { message: "Receiver User not found" }, status: :unauthorized unless receiver

    user = User.find_by(id: receiver.companion_id)
    return render json: { message: "Receiver's Stripe Connect Account Doesn't exist" }, status: :unauthorized unless user.stripe_connect_id?

    validate = Stripe::Account.retrieve(user.stripe_connect_id)
    return render json: { message: "Receiver User Stripe Connect not verified" }, status: :unauthorized unless validate.details_submitted

    amount_in_cents = amount_to_cents(params[:amount])
    charge, transfer = process_transfer(user, amount_in_cents)

    if charge && transfer
      balance = retrieve_stripe_balance
      transfer_record = create_transaction("Transfer", charge.amount / 100, "Credit Card")
      if transfer_record.save
        render json: build_transfer_response(charge, balance, receiver, user)
      else
        render json: { message: "Transfer Not Successful" }, status: :unauthorized
      end
    end
  rescue => e
    render json: { message: e.message }, status: :unauthorized
  end

  def withdraw
    return render json: { message: "Insufficient Funds" }, status: :unauthorized unless sufficient_funds?(params[:amount])

    amount_in_cents = amount_to_cents(params[:amount])
    withdraw = process_withdraw(amount_in_cents)

    if withdraw
      balance = retrieve_stripe_balance
      payout = create_transaction("Withdraw", withdraw.amount / 100, "Bank")
      if payout.save
        render json: build_withdraw_response(withdraw, balance)
      else
        render json: { message: "Withdraw Not Successful" }, status: :unauthorized
      end
    end
  rescue => e
    render json: { message: e.message }, status: :unauthorized
  end

  def transaction_history
    transactions = current_user.transactions.order(created_at: :desc)
    payments = current_user.payments.order(created_at: :desc)

    if transactions.present? || payments.present?
      render json: (transactions + payments).sort_by(&:created_at).reverse
    else
      render json: { message: "No transactions available" }, status: :no_content
    end
  end

  private

  def check_stripe_connect_account
    account = Stripe::Account.retrieve(current_user.stripe_connect_id)
    unless account.details_submitted && account.requirements.disabled_reason.nil?
      render json: { message: "Verify your Stripe Connect details first" }, status: :unauthorized
    end
  end

  def amount_to_cents(amount)
    (amount.to_f * 100).to_i
  end

  def sufficient_funds?(amount)
    balance = retrieve_stripe_balance
    amount.to_f <= (balance['instant_available'][0]['amount'] / 100)
  end

  def retrieve_stripe_balance
    Stripe::Balance.retrieve({ stripe_account: current_user.stripe_connect_id })
  end

  def create_transaction(method, amount, source_type)
    Transaction.create(
      user_id: current_user.id,
      transaction_no: "AHU" + SecureRandom.hex(5),
      method: method,
      amount: amount,
      source_type: source_type
    )
  end

  def process_topup(card, amount_in_cents)
    charge = Stripe::Charge.create(
      amount: amount_in_cents,
      currency: "usd",
      source: card.token,
      customer: current_user.stripe_customer_id
    )
    transfer = Stripe::Transfer.create(
      amount: amount_in_cents,
      currency: "usd",
      destination: current_user.stripe_connect_id
    )
    [charge, transfer]
  end

  def process_transfer(user, amount_in_cents)
    charge = Stripe::Charge.create(
      amount: amount_in_cents,
      currency: "usd",
      source: current_user.stripe_connect_id,
      customer: current_user.stripe_customer_id
    )
    transfer = Stripe::Transfer.create(
      amount: amount_in_cents,
      currency: "usd",
      destination: user.stripe_connect_id
    )
    [charge, transfer]
  end

  def process_withdraw(amount_in_cents)
    Stripe::Payout.create({
      amount: amount_in_cents,
      currency: "usd",
    }, {
      stripe_account: current_user.stripe_connect_id
    })
  end

  def build_response(message, charge, balance, card)
    {
      message: message,
      amount: charge.amount / 100,
      method: "Credit Card",
      Transaction_id: charge[:balance_transaction],
      Current_TextNG_Wallet_Balance: balance["available"][0]["amount"] / 100,
      Full_Name: card.card_holder_name,
      Card_Number: card.cvc,
      Expiry: "#{card.expiry_month}/#{card.expiry}"
    }
  end

  def build_transfer_response(charge, balance, receiver, user)
    {
      message: "Transfer Successful",
      amount: charge.amount / 100,
      TextNG_Charge: "3.00",
      Currency_Type: charge[:currency],
      source: "Credit Card",
      Transferred_to: receiver.name,
      TextNG_Number: user.textng_number,
      Transaction_id: charge[:balance_transaction],
      Wallet_Balance: balance["available"][0]["amount"] / 100
    }
  end

  def build_withdraw_response(withdraw, balance)
    {
      message: "Withdraw Successful",
      amount: withdraw[:amount] / 100,
      Transaction_id: withdraw[:balance_transaction],
      Current_TextNG_Wallet_Balance: balance["available"][0]["amount"] / 100,
      Full_Name: current_user.cards.first.card_holder_name,
      Card_Number: current_user.cards.first.cvc,
      Expiry: "#{current_user.cards.first.expiry_month}/#{current_user.cards.first.expiry}"
    }
  end
end
