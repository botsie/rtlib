require 'mongo'
require 'rt/client'
require File.expand_path("../lib/rt.rb", __FILE__)



class ImportTicketsApp
  RT_SERVER = "sysrt.directi.com"
  RT_SERVER_PORT = 443
  RT_USERNAME = "biju.ch"
  RT_PASSWORD = "Abc@123"
  RT_USE_SSL = true

  MONGO_SERVER = "localhost"
  MONGO_DB = "rt"
  MONGO_USER = "rt-dash"
  MONGO_PASSWORD = "password"
  
  def initialize
    @rt = RT::Server.new( :server => RT_SERVER,
                          :port => RT_SERVER_PORT,
                          :user => RT_USERNAME,
                          :password => RT_PASSWORD,
                          :use_ssl => RT_USE_SSL )
                       
    @mongo_server = Mongo::Connection.new(MONGO_SERVER)
    @mongo_server.add_auth(MONGO_DB, MONGO_USER, MONGO_PASSWORD)
    @mongo = @mongo_server[MONGO_DB]
  end
  
  def run
    push tickets, :to_tickets
    push ticket_history, :to_history
#    puts "RT Tickets: ", tickets.length.to_s
#    puts "Mongo Tickets: , 
  end

  def tickets
    @tickets = @rt.tickets_where("Queue='automation'").collect {|t| t.to_hash } unless @tickets
    return @tickets
  end

  def ticket_history
    unless @history
      @history = Array.new
      tickets.each do |ticket|
        begin
          @history << @rt.history_of(ticket['id'])
        rescue Timeout::Error
          next
        end
      end
      @history.flatten!
    end
    return @history
  end

  def push( collection, target )
    if target == :to_tickets
      coll = @mongo['tickets']
    elsif target == :to_history
      coll = @mongo['history']
    end

    collection.each do |item|
      coll.insert(item)
    end
  end
end

app = ImportTicketsApp.new
app.run

  

