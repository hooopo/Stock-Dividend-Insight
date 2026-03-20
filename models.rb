require 'active_record'

class Stock < ActiveRecord::Base
  has_many :price_histories, dependent: :destroy
end

class PriceHistory < ActiveRecord::Base
  belongs_to :stock
end
