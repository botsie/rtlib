require 'pp'
require File.expand_path("../../models/rt.rb", __FILE__)



class RTApp
  RT_SERVER = "sysrt.directi.com"
  RT_SERVER_PORT = 443
  RT_USERNAME = "biju.ch"
  RT_PASSWORD = "Abc@123"
  RT_USE_SSL = true
  
  def initialize
    @rt = RT::Server.new( :server => RT_SERVER,
                          :port => RT_SERVER_PORT,
                          :user => RT_USERNAME,
                          :password => RT_PASSWORD,
                          :use_ssl => RT_USE_SSL )
    @q = RT::Query.new(@rt)
  end
  
  def run(query)
    res = eval "@q.#{query}.execute"
    puts res.to_s
  end
end

app = RTApp.new
app.run ARGV[0]

  
