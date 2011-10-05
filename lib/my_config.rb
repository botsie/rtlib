require 'yaml'

class MyConfig

  def initialize(data={})
    @data = Hash.new
    update!(data)
  end

  def update!(data)
    data.each do |key, value|
      cleaned_key = key.to_s.gsub('^:','')
      self[cleaned_key] = value
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

  def to_yaml( opts = {} )
    @data.to_yaml( opts )
  end

end
