class ResumesController < ApplicationController
  require "json"
  require "fileutils"

  def new
  end

  def create
    uploaded_file = params[:resume]

    return render plain: "Please select a file" unless uploaded_file.present?

    upload_dir = Rails.root.join("public", "resumes")
    FileUtils.mkdir_p(upload_dir)

    data_file = Rails.root.join("public", "data.json")

    # Read existing json
    existing_data =
      if File.exist?(data_file)
        JSON.parse(File.read(data_file)) rescue {}
      else
        {}
      end

    # Delete old file if exists
    if existing_data["filename"].present?
      old_file = upload_dir.join(existing_data["filename"])

      File.delete(old_file) if File.exist?(old_file)
    end

    # Save new file
    filename = uploaded_file.original_filename
    filepath = upload_dir.join(filename)

    File.open(filepath, "wb") do |file|
      file.write(uploaded_file.read)
    end

    # Replace json data
    new_data = {
      filename: filename,
      uploaded_at: Time.now
    }

    File.write(data_file, JSON.pretty_generate(new_data))

    render plain: "Resume replaced successfully"
  end
end
