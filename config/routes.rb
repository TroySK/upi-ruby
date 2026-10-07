# frozen_string_literal: true

UPI::Engine.routes.draw do
  post "webhooks/:provider" => "webhooks#create"
end
