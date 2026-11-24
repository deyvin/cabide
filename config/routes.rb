Rails.application.routes.draw do
  root "garments#index"

  resources :garments, only: %i[index create destroy] do
    post :retry, on: :member
  end

  resources :photos, only: [] do
    post :regenerate, on: :member
  end

  resources :videos, only: %i[create destroy] do
    post :retry, on: :member
    post :regenerate, on: :member
  end

  scope :higgsfield, controller: :higgsfield_connections do
    get :connect, action: :new, as: :connect_higgsfield
    get :callback, as: :higgsfield_callback
    delete :connection, action: :destroy, as: :higgsfield_connection
  end
  resource :balance, only: :show

  get "up" => "rails/health#show", as: :rails_health_check
end
