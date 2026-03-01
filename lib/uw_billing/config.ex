defmodule UwBilling.Config do
  use Ash.Domain

  resources do
    resource UwBilling.Config.StripeConfig do
      define :get_stripe_config, action: :current
      define :get_stripe_config_any, action: :current_any
      define :save_stripe_config, action: :save
      define :disable_stripe_config, action: :disable
    end
  end
end
