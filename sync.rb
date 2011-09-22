require 'yaml'
require 'logger'
require File.expand_path("../models/rt.rb", __FILE__)
require File.expand_path("../models/tickets.rb", __FILE__)
require 'pp'

class MyConfig

  def initialize(data={})
    @data = {}
    update!(data)
  end

  def update!(data)
    data.each do |key, value|
      self[key] = value
    end
  end

  def [](key)
    @data[key.to_sym]
  end

  def []=(key, value)
    if value.class == Hash
      @data[key.to_sym] = MyConfig.new(value)
    else
      @data[key.to_sym] = value
    end
  end

  def method_missing(sym, *args)
    if sym.to_s =~ /(.+)=$/
      self[$1] = args.first
    else
      self[sym]
    end
  end

  def to_yaml
    @data.to_yaml
  end

end

class SyncApp
  
  def initialize
    @config = MyConfig.new(YAML.load_file(File.expand_path("../config/sync.yml", __FILE__)))
    # @log = Logger.new(@config.log.file)
    @log = Logger.new(STDOUT)
    @log.level = Logger.const_get(@config.log.level.to_sym)
          
    Mongoid.logger = @log
    Mongoid.configure do |config|
      config.master = Mongo::Connection.new.db("rt")
      config.master.authenticate('rt-dash', 'password')
    end
    
    @rt = RT::Server.new( :server => @config.rt.server,
                          :port => @config.rt.port,
                          :user => @config.rt.user,
                          :password => @config.rt.password,
                          :use_ssl => @config.rt.ssl )
  end
  
  def run
    timestamp = Time.now
    push tickets
  end

  def tickets
    if not @tickets
      @log.info "fetching tickets"
      query = @rt.query
      last_sync = DateTime.parse(@config.last_sync).rfc2822
      @tickets = query.where('Queue').in(*@config.rt.queues).and('LastUpdated').after(last_sync).execute
      @tickets.each do |ticket|
        @log.info "Fetching history for #{ticket['id']}"
        ticket['history'] = @rt.history_of(ticket)
      end
    end
    return @tickets
  end

  def push( tickets )
    tickets.each do |rt_ticket|
      ticket = Ticket.find_or_create_by(rt_id: rt_ticket['id'])

      # ticket = Ticket.find(:first, :condition => {:rt_id => rt_ticket['id']})
      # ticket = Ticket.new # unless ticket
    
      update_rule = {
        'id' => Proc.new { |key, value| ticket['rt_id'] = value },
        'history' => Proc.new { |key, value| append_history ticket, value }
      }
      update_rule.default = Proc.new do |key, value|
        value = nil if value == "Not set"
        ticket[key] = value
      end

      rt_ticket.each_pair do |key, value|
        @log.info "Syncing #{rt_ticket['id']}.#{key} = #{value}"
        update_rule[key].call(key, value)
      end
      
      ticket.save
    end
  end

  def append_history( ticket, history )
    history.each do |history_item|
      @log.info "\t#{history_item['id']}"
      existing_update = ticket.updates.where(rt_id: history_item['id'])
      if existing_update.empty?
        update = Update.new
        update['rt_id'] = history_item['id']
        history_item.each_pair do |key, value|
          unless key == 'id'
            @log.info "\t\tSyncing #{key}:#{value}"
            update[key] = value
          end
        end
      end
      ticket.updates << update
    end
  end
end

app = SyncApp.new
app.run

  

