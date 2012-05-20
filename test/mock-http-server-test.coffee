vows      = require 'vows'
assert    = require 'assert'
http      = require 'http'
{_}       = require 'underscore'
helpers   = require '../lib/helpers'

{responseWrapper, testHTTPRunning, requestOptions} = helpers

HOSTNAME      = '127.0.0.1'
HTTPPORT      = 7771

http.createServer((req, res) ->
  unknownRequest = ->
    res.writeHead 404
    res.end()

  # Simple HTTP Server used for testing the proxy
  switch req.method
    when 'GET'
      switch req.url
        when '/'
          res.writeHead 200, "Content-Type": "text/plain"
          res.end ""
        when '/texttest'
          res.writeHead 200, "Content-Type": "text/plain"
          res.end "texttest"
        when '/jsontest'
          res.writeHead 200, "Content-Type": "application/json"
          res.end(JSON.stringify({ jsontest: true }))
        else
          unknownRequest()
    else
      unknownRequest()
).listen HTTPPORT, HOSTNAME

getRequest = (path, callback) ->
  req = http.request requestOptions(HOSTNAME, HTTPPORT, path), responseWrapper(callback)
  req.end()
  return

# postRequest = (path, options, callback) ->
#   {options, body} = postJSONOptions HOSTNAME, HTTPPORT, path, options
#   req = http.request options, responseWrapper callback
#   req.write body
#   req.end()
#   return
# postRender = (features, callback) ->
#   postRequest '/render', features, callback


vows.describe('Mock HTTP Server Test (mock-http-server-test)')
  .addBatch
    'The HTTP Server': testHTTPRunning "", HTTPPORT

  .addBatch
    'Getting text from an API':
      topic: ->
        getRequest '/texttest', @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 200 and have text data': (getRequest) ->
        assert.equal getRequest.statusCode, 200
        assert.equal getRequest.headers['content-type'], "text/plain"
        assert.equal getRequest.body, 'texttest'

    'Getting JSON from an API':
      topic: ->
        getRequest '/jsontest', @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 200 and have JSON data': (getRequest) ->
        assert.equal getRequest.statusCode, 200
        assert.equal getRequest.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(getRequest.body), { jsontest: true }


  .export(module)
