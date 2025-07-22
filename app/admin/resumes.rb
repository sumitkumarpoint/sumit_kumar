ActiveAdmin.register Resume do
  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  # permit_params :first_name, :last_name, :phone_number, :email, :summery
  #
  # or
  form do |f|
    f.inputs "Details" do
      f.input :first_name
      f.input :last_name
      f.input :phone_number
      f.input :email
      f.input :summery
      f.input :current

      # Always show file input for uploading image
      f.input :image, as: :file

      # Show preview only if image is attached
      if f.object.image.attached?
        div do
          image_tag url_for(f.object.image), style: 'max-width: 200px;'
        end
      end
    end

    f.actions
  end


  permit_params do
    permitted = [ :first_name, :last_name, :phone_number, :email, :summery, :current, :image ]
    permitted << :other if params[:action] == "create"
    permitted
  end
end
