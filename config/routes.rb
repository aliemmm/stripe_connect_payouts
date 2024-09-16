Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
        
     resources :stripe_connect, only: [] do
        collection do
          post :connect
          get :balance_check
          get :login_link
          get :retrieve
        end
      end

      resources :checkout, only: [] do
        collection do
          post :create_charge_for_theme
          post :create_charge_for_burn_number
          post :apple_pay_theme
          post :apple_pay_burn_number
          post :google_pay_theme
          post :google_pay_burn_number
        end
      end
      
      resources :transactions, only: [] do
        collection do
          post :topup
          post :transfer
          post :withdraw
          get :transaction_history
        end
      end
    end
  end
end
