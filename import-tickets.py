import urllib
import urllib2
import cookielib
import pprint
import email

class RTServer:
    """Understands RT's REST interface"""

    def __init__(self):
        self.user = "biju.ch"
        self.password = "Abc@123"
        self.base_url = "http://sysrt.directi.com"
        self.api_context = "/REST/1.0"
        
        self.login()

    def login(self):
        data = urllib.urlencode({"user": self.user,  "pass": self.password})

        cookie_jar = cookielib.CookieJar()
        self.http = urllib2.build_opener(urllib2.HTTPCookieProcessor(cookie_jar))

        response = self.http.open(self.base_url + '/index.html', data)


    def get(self, url):
        full_url = self.base_url + self.api_context + url
        escaped_url = urllib.quote_plus(full_url, ':/')

        response = self.http.open(escaped_url)
        data = response.read()

        return data

class RT:
    """Understands How to Build RT Domain Objects"""
    

rt_server = RTServer()
data = rt_server.get('/ticket/13115/show')
pprint.pprint(data)
        
