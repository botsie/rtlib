require 'net/http'
require 'net/https'
require 'singleton'
require 'uri'
require 'rmail'
require 'pp'
          
DEBUG=true



def log(*msgs)
  pp *msgs if DEBUG
end

module RT

  class Server
    
    def initialize(params)
      @server = params[:server]
      @port = params[:port]
      @user = params[:user]
      @password = params[:password]
      @use_ssl = params[:use_ssl]
      
      @url_prefix = '/REST/1.0'

      @http = Net::HTTP.new(@server, @port)
      @http.use_ssl = @use_ssl
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      # @http.set_debug_output $stderr if DEBUG
      login
    end

    private

    def login
      login = "user=#{@user}&pass=#{@password}"
      headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
      resp, data = @http.post('/index.html', login, headers)
      pp resp.response['set-cookie']
      @cookie = resp.response['set-cookie'].split('; ')[0]
      pp @cookie
    end

    public

    def get(url)

      log("http://#{@server}:#{@port}#{@url_prefix}#{url}")

      headers = { 'Cookie' => @cookie }
      resp, data = @http.get2(URI.escape(@url_prefix + url), headers)
      return data
    end

    def ticket(id)
      url  = "/ticket/#{id}/show"
      Document.new(get(url))
    end

    def tickets_where(condition)
      url = "/search/ticket?query=#{condition}&format=l"
      tickets = Array.new
      
      get(url).split('--').each do |ticket_data|
        tickets.push(Document.new(ticket_data))
      end
      return tickets
    end

    def history_of(ticket)
      if ticket.class == Document
        id = ticket.id
      elsif ticket.class == Hash
        id = ticket['id']
      elsif ticket.class == String
        id = ticket
      end
      id = id.gsub(/^ticket\//,"")
      url = "/ticket/#{id}/history?format=l"
      history = Array.new
      
      get(url).split('--').each do |history_item_data|
        history.push(Document.new(history_item_data))
      end
      return history
    end
  end

  module RTParser

    def parse( data_string )

      data_string.gsub!(/RT\/\d+\.\d+\.\d+\s\d{3}\s.*\n\n/,"") # toss the HTTP response
      data_string.gsub!(/\n\n/,"\n") # remove double spacing
      data_string.gsub!(/^\n/,"") # RMail barfs on Messages that start with a newline

      data = RMail::Parser.read(data_string).header
      out = Hash.new

      # Convert from RMail::Header to vanilla Hash
      out = Hash.new
      data.each do |key, value|
        cleaned_key = key.gsub(/\./,"_") # Mongo doesn't like periods in key names
        out[cleaned_key] = value
      end
      return out
    end
  end
  
  class Document
    include RTParser
    
    def self.delegate_to_db_hash(*methods)
      methods.each do |method|
        define_method method.to_s do |*args|
          return @db.send method.to_sym, *args
        end
      end
    end

    delegate_to_db_hash :keys, :values, :has_key?
    
    def initialize(data)
      # pp data, "--"
      @data = data
      @db = parse(data)
    end

    def to_s
      s = ''
      @db.each_pair do |key, value|
        s += "#{key}: #{value}\n"
      end
      return s
    end

    def to_hash
      return @db
    end

    def [](key)
      @db[key]
    end
  end

  class Query
    def self.aggregators(*args)
      args.each do |arg|
        define_method arg do |name|
          @aggregated_fields.push AggregatedField.new(name, arg)
          return self
        end
      end
    end

    def self.delegate_to_current_where_field(*methods)
      methods.each do |method|
        define_method method.to_s do |*args|
          @current_where_field.send method.to_sym, *args
          return self
        end
      end
    end

    aggregators :count, :sum
    delegate_to_current_where_field :is, :is_not, :in, :not_in, :on, :is_not_on
    delegate_to_current_where_field :less_than, :greater_than, :before, :after
    
    def initialize(server)
      @where_fields = Hash.new
      @aggregated_fields = Array.new
      @group_by = Array.new
      @server = server
    end

    def group_by(*field_names)
      field_names.each { |field| @group_by << field }
      return self
    end
    
    def where(name)
      unless @where_fields.has_key? name then 
        @where_fields[name] = WhereField.new(name)
      end
      @current_where_field = @where_fields[name]
      return self
    end
    alias :and :where

    def query()
      conditions = Array.new
      @where_fields.each_value do |field|
        conditions.push field.render
      end

      if conditions.length > 1 then
        return "#{conditions.join(' AND ')}"
      elsif conditions.length == 1 then
        return conditions[0]
      end
      return ""
    end

    def execute()

      results = @server.tickets_where(query)
      return results if @aggregated_fields.empty?

      groups = Hash.new
      
      results.each do |result|
        current_group = group_of result
        if not groups.has_key? current_group
          ary = @aggregated_fields.collect { |f| f.clone }
          if current_group != :all
            a = @group_by.collect { |f| AggregatedField.new(f, :grouped_by) }
            ary = a.concat(ary)
          end
          groups[current_group] = ary
        end
        groups[current_group].each { |field| field.aggregate(result) }
      end

      result_rows = Array.new
      groups.values.each do |group|
        row = Hash.new
        group.each do |field|
          row[field.name] = field.aggregated_value
        end
        result_rows << row
      end
      return result_rows
    end

    def group_of(row)
      if @group_by.empty?
        return :all
      else
        return @group_by.collect { |fld| row[fld] }.join
      end
    end
  end

  class AggregatedField

    attr_accessor :field_name, :op, :aggregated_value
    
    def initialize(field_name, op)
      @field_name = field_name
      @op = op
      @aggregated_value = nil
    end

    def name
      return op.to_s + '_' + @field_name
    end

    def aggregate(value)
      m = self.method(@op)
      m.call(value)
    end

    def count(row)
      if @aggregated_value
        @aggregated_value += 1
      else
        @aggregated_value = 1
      end
    end

    def grouped_by(row)
      @aggregated_value = row[field_name]
    end
  end

  class WhereField
    def self.array_comparators(*args)
      args.each do |arg|
        define_method arg do |*values|
          add_condition arg, values
        end
      end
    end

    def self.unary_comparators(*args)
      args.each do |arg|
        define_method arg do |value|
          @conditions[arg] =  value 
        end
      end
    end

    array_comparators :in, :not_in
    unary_comparators :less_than, :greater_than
    alias :on :in
    alias :is_not_on :not_in
    alias :is :in
    alias :is_not :not_in
    alias :before :less_than
    alias :after :greater_than
    
    def initialize(name)
      @name = name
      @conditions = {}
      @operators = {
        :in => '=',
        :not_in => '!=',
        :less_than => '<',
        :greater_than => '>'
      }

      @aggregators = {
        :in => ' OR ',
        :not_in => ' AND '
      }
    end

    def add_condition(op, values)
      @conditions[op] = [] unless @conditions.has_key? op
      @conditions[op].concat values
      return self
    end

    def between(first, second)
      less_than(first)
      greater_than(second)
      return self
    end

    def render
      clauses = []
      @conditions.each_pair do | op, values |
        clause = render_clause op, values
        clauses.push clause 
      end
      if clauses.length > 1 then
        return "( #{clauses.join(' AND ')} )"
      elsif clauses.length == 1 then
        return clauses[0]
      end
      return ""
    end

    def render_clause(op, values)
      subclauses = values.map do |value|
        value = "'#{value}'" if value.is_a?String
        "#{@name} #{@operators[op]} #{value}"
      end
      if subclauses.length > 1 then
        return "( #{subclauses.join(@aggregators[op])} )"
      elsif subclauses.length == 1 then
        return subclauses[0]
      end
    end
  end    

end


