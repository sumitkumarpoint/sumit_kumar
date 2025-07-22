class HomesController < ApplicationController
  def index
    @resume = Resume.find_by(current: true)
  end

  def resume
  end
end
