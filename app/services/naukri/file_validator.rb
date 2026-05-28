# app/services/naukri/file_validator.rb
module Naukri
  class FileValidator
    CONFIG = Rails.application.config_for(:naukri).freeze

    MAX_SIZE_BYTES     = (CONFIG[:max_file_size_mb] || 2) * 1024 * 1024
    ALLOWED_EXTENSIONS = (CONFIG[:allowed_extensions] || [".pdf", ".doc", ".docx"]).freeze

    attr_reader :errors

    def initialize(file_path)
      @file_path = file_path
      @errors    = []
    end

    def valid?
      @errors = []
      check_file_exists
      check_extension
      check_file_size
      @errors.empty?
    end

    def mime_type
      case File.extname(@file_path).downcase
      when ".pdf"  then "application/pdf"
      when ".doc"  then "application/msword"
      when ".docx" then "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      else              "application/octet-stream"
      end
    end

    private

    def check_file_exists
      @errors << "File not found: #{@file_path}" unless File.exist?(@file_path)
    end

    def check_extension
      ext = File.extname(@file_path).downcase
      unless ALLOWED_EXTENSIONS.include?(ext)
        @errors << "Invalid file type '#{ext}'. Allowed: #{ALLOWED_EXTENSIONS.join(', ')}"
      end
    end

    def check_file_size
      return unless File.exist?(@file_path)

      size = File.size(@file_path)
      if size > MAX_SIZE_BYTES
        mb = (size / 1024.0 / 1024.0).round(2)
        @errors << "File too large (#{mb}MB). Maximum allowed: #{CONFIG[:max_file_size_mb]}MB"
      end
    end
  end
end
