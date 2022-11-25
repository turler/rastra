Rails.application.routes.draw do
  resources :pairs, :statics
  root 'statics#index'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"

  resources :bots do
    member do
      get 'start'
      get 'stop'
    end
  end
end
