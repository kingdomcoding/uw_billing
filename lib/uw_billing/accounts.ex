defmodule UwBilling.Accounts do
  use Ash.Domain

  resources do
    resource UwBilling.Accounts.User do
      define :create_user, action: :create
      define :update_user, action: :update
      define :get_user_by_api_key, action: :by_api_key, args: [:api_key]
      define :get_user_by_stripe_customer, action: :by_stripe_customer, args: [:stripe_customer_id]
      define :list_users, action: :read
    end
  end
end
