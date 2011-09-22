require 'mongoid'

class Ticket
  include Mongoid::Document
  
  # Fields
  field :Created, type: DateTime
  field :Starts, type: DateTime
  field :Started, type: DateTime
  field :Due, type: DateTime
  field :Resolved, type: DateTime
  field :Told, type: DateTime
  field :LastUpdated, type: DateTime

  # Subdocuments
  embeds_many :updates
end

class Update
  include Mongoid::Document
  embedded_in :ticket
end

