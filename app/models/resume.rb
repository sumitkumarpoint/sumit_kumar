class Resume < ApplicationRecord
    include Ransackable
    has_one_attached :image
end
