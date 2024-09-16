class User < ApplicationRecord
  before_destroy :destroy_associated_rooms
  scope :all_except, ->(user) { where.not(id: user) }

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  validates :phone_number, uniqueness: true, if: :phone_number
  has_many :notifications, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :cards, dependent: :destroy

  validates :stripe_customer_id, uniqueness: true
  before_validation :create_stripe_reference, on: :create

  has_many :payments, dependent: :destroy

  has_many :banks, dependent: :destroy

  def create_stripe_reference
    response = Stripe::Customer.create(email: email)
    self.stripe_customer_id = response.id
  end

  def retrieve_stripe_reference
    Stripe::Customer.retrieve(stripe_customer_id)
  end
end
