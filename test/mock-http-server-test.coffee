vows      = require 'vows'
assert    = require 'assert'
http      = require 'http'
{_}       = require 'underscore'
helpers   = require '../lib/helpers'

{responseWrapper, testHTTPRunning, requestOptions} = helpers

HOSTNAME      = '127.0.0.1'
HTTPPORT      = 7771

createBinaryImageData = ->
  size = 1 * 1024 * 1024
  data = new Buffer(size)
  i = 0
  while i < size
    data.writeUInt8((i % 256), i)
    i++
  data

testImageData = createBinaryImageData()

  # Simple HTTP Server used for testing the proxy
http.createServer((req, res) ->
  unknownRequest = -> res.writeHead 404
  switch req.method
    when 'GET'
      switch req.url
        when '/'
          res.writeHead 200, "Content-Type": "text/plain"
        when '/texttest'
          res.writeHead 200, "Content-Type": "text/plain"
          res.write "texttest"
        when '/jsontest'
          res.writeHead 200, "Content-Type": "application/json"
          res.write JSON.stringify({ jsontest: true })
        when '/imagetest'
          res.writeHead 200, "Content-Type": "image/png"
          res.write testImageData
        else
          unknownRequest()
    else
      unknownRequest()
  res.end()
).listen HTTPPORT, HOSTNAME

getRawRequest = (path, callback, encoding) ->
  http.request(requestOptions(HOSTNAME, HTTPPORT, path), responseWrapper(callback, encoding)).end()
  return

getRequest = (path, callback) -> getRawRequest(path, callback, 'utf8')
getImageRequest = (path, callback) -> getRawRequest(path, callback)

vows.describe('Mock HTTP Server Test (mock-http-server-test)')
  .addBatch
    'The HTTP Server': testHTTPRunning "The test creates the server and it is not running", HTTPPORT

  .addBatch
    'Getting an unknown page':
      topic: ->
        getRequest '/does-not-exit', @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 404': (getRequest) ->
        assert.equal getRequest.statusCode, 404

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

    'Getting large binary data from an API':
      topic: ->
        getImageRequest '/imagetest', @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 200 and have image data': (getRequest) ->
        assert.equal getRequest.statusCode, 200
        assert.equal getRequest.headers['content-type'], "image/png"
      'should have the same binary image sent by the server': (getRequest) ->
        if getRequest.body.toString('base64') != testImageData.toString('base64')
          assert.isTrue false, "Image received (#{getRequest.body.length} bytes) is not the same as file (#{testImageData.length} bytes)"

  .export(module)

