# app/services/naukri/result.rb
module Naukri
  class Result
    attr_reader :data, :error

    def initialize(success:, data: {}, error: nil)
      @success = success
      @data    = data
      @error   = error
    end

    def self.success(data = {})
      new(success: true, data: data)
    end

    def self.failure(error, data = {})
      new(success: false, data: data, error: error)
    end

    def success?
      @success
    end

    def failure?
      !@success
    end

    def to_h
      { success: success?, data: @data, error: @error }
    end

    def inspect
      "#<Naukri::Result success=#{success?} data=#{@data} error=#{@error}>"
    end
  end
end
