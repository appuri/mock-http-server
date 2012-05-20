http        = require 'http'
assert      = require 'assert'
querystring = require 'querystring'

responseWrapper = exports.responseWrapper = (handler) ->
  (response) ->
    response.body = ''
    response.on 'error', (e) -> handler e
    response.on 'data', (chunk) -> response.body += chunk
    response.on 'end', () ->
      result =
        headers: response.headers
        statusCode: response.statusCode,
        body: response.body
      handler null, result

testHTTPRunning = exports.testHTTPRunning = (message, port=80, hostname='localhost') -> {
    topic: ->
      callback = @callback
      client = http.createClient port, hostname
      client.on 'error', (error) ->
        callback error, null
      req = client.request 'GET', '/'
      req.on 'response', responseWrapper(@callback)
      req.end()
      return

    'should be running': (error, response) ->
      if error or not response
        console.error "\n\n#{error}\n\n#{message}\n\n"
        throw "HTTP server not running"
      else
        assert.equal response.statusCode, 200
  }

requestOptions = exports.requestOptions = (host, port, path = '/', method = 'GET', contentType = 'application/json') ->
  options =
    host: host
    port: port
    method: method
    path: path

  if method == 'POST'
    options.headers =
      'Content-Type': contentType
      'Content-Length': 0
  options
