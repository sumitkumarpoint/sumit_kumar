Rails.application.routes.draw do
  # devise_for :admin_users, ActiveAdmin::Devise.config
  # ActiveAdmin.routes(self)
  get "homes/index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  root "homes#index"
  get "homes/resume", "homes#resume"
  get  "/resume_upload", to: "resumes#new"
  post "/resume_upload", to: "resumes#create"
  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "/resume/upload_naukari", to: "resumes#upload_naukari"
  get "/resume/login", to: "resumes#login"
  # Defines the root path route ("/")
  # root "posts#index"
  get '/naukri/login', to: 'naukri_login#index', as: 'naukri_login_page'
  post '/naukri/login', to: 'naukri_login#login', as: 'naukri_login'
  post '/naukri/verify-otp', to: 'naukri_login#verify_otp', as: 'naukri_verify_otp'
  post '/naukri/logout', to: 'naukri_login#logout', as: 'naukri_logout'
  get '/naukri/status', to: 'naukri_login#status', as: 'naukri_status'
  get '/naukri/session-info', to: 'naukri_login#session_info', as: 'naukri_session_info'
end
