vows      = require 'vows'
assert    = require 'assert'
http      = require 'http'
{_}       = require 'underscore'
helpers   = require '../lib/helpers'

{responseWrapper, testHTTPRunning, requestOptions, postJSONOptions} = helpers

HOSTNAME      = '127.0.0.1'
HTTPPORT      = 7771

#
# Binary data used for testing
#

createBinaryImageData = ->
  size = 1 * 1024 * 1024
  data = new Buffer(size)
  i = 0
  while i < size
    data.writeUInt8((i % 256), i)
    i++
  data

testImageData = createBinaryImageData()

#
# Simple HTTP Server used for testing the proxy
#
unknownRequest = (res) -> res.writeHead 404

verifyGetRequest = (req, res) ->
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
      unknownRequest res
  res.end()

verifyPostRequest = (req, res) ->
  switch req.url
    when '/posttest'
      body = JSON.parse(req.body)
      if body.test == 'posttest'
        res.writeHead 200, "Content-Type": "application/json"
        res.write JSON.stringify({ posttest: true })
      else
        res.writeHead 422, "Unprocessable Entity", "Content-Type": "text/plain"
    else
      unknownRequest res
  res.end()

http.createServer((req, res) ->
  switch req.method
    when 'GET'
      # Respond immediately
      verifyGetRequest(req, res)
    when 'POST'
      # Collect the body
      req.body = ''
      req.on 'data', (chunk) -> req.body += chunk
      req.on 'end', -> verifyPostRequest(req, res)
    else
      unknownRequest res
      res.end()
).listen HTTPPORT, HOSTNAME

#
# Test Macros
#

getRawRequest = (path, callback, encoding) ->
  http.request(requestOptions(HOSTNAME, HTTPPORT, path), responseWrapper(callback, encoding)).end()
  return

getRequest = (path, callback) -> getRawRequest(path, callback, 'utf8')
getImageRequest = (path, callback) -> getRawRequest(path, callback)

postRequest = (path, params, callback) ->
  {options, body} = postJSONOptions HOSTNAME, HTTPPORT, path, params
  req = http.request options, responseWrapper(callback, 'utf8')
  req.write body
  req.end()
  return

#
# Test Suite
#

vows.describe('Mock HTTP Server Test (mock-http-server-test)')
  .addBatch
    'The HTTP Server': testHTTPRunning "The test creates the server and it is not running", HTTPPORT

  .addBatch
    'Getting an unknown page':
      topic: ->
        getRequest '/does-not-exit', @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 404': (results) ->
        assert.equal results.statusCode, 404

    'Getting text from an API':
      topic: ->
        getRequest '/texttest', @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 200 and have text data': (results) ->
        assert.equal results.statusCode, 200
        assert.equal results.headers['content-type'], "text/plain"
        assert.equal results.body, 'texttest'

    'Getting JSON from an API':
      topic: ->
        getRequest '/jsontest', @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 200 and have JSON data': (results) ->
        assert.equal results.statusCode, 200
        assert.equal results.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(results.body), { jsontest: true }

    'Getting large binary data from an API':
      topic: ->
        getImageRequest '/imagetest', @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 200 and have image data': (results) ->
        assert.equal results.statusCode, 200
        assert.equal results.headers['content-type'], "image/png"
      'should have the same binary image sent by the server': (results) ->
        if results.body.toString('base64') != testImageData.toString('base64')
          assert.isTrue false, "Image received (#{results.body.length} bytes) is not the same as file (#{testImageData.length} bytes)"

  .addBatch
    'Posting to an unknown page':
      topic: ->
        postRequest '/does-not-exit', {}, @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 404': (results) ->
        assert.equal results.statusCode, 404

    'Posting to an API':
      topic: ->
        postRequest '/posttest', { test: 'posttest' }, @callback
      'should not have errors': (error, results) ->
        assert.isNull error
      'should respond with HTTP 200': (results) ->
        assert.equal results.statusCode, 200

  .export(module)

