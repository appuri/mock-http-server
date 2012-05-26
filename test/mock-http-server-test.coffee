#
# This test suite starts HTTP and HTTPS servers, a recording proxy
# and a playback server.
# 
# The test batches mostly test that the same requests return from
# each server.  Therefore you
# The fixture data is stored in ./test/fixtures
#
vows      = require 'vows'
assert    = require 'assert'
fs        = require 'fs'
http      = require 'http'
https     = require 'https'
{_}       = require 'underscore'
helpers   = require '../test/helpers'
mock      = require '../src/mock-http-server'

{responseWrapper, testHTTPRunning, requestOptions, postJSONOptions} = helpers
{createRecordingProxyServer, createPlaybackServer} = mock

HOSTNAME      = '127.0.0.1'
HTTPPORT      = 7771  # Target HTTP server
PROXYPORT     = 7772  # Recording Proxy Server
PLAYBACKPORT  = 7773  # Playback HTTP server
HTTPSPORT     = 7774  # Target HTTPS server

#
# Binary data used for testing large HTTP response bodies
#

createBinaryImageData = ->
  size = 1 * 1024 * 1024
  data = new Buffer(size)
  i = 0
  while i < size
    data.writeUInt8((i % 256), i)
    i++
  data

TEST_IMAGE_DATA = createBinaryImageData()

#
# A simple HTTP server that is used as the target
# for the recording proxy
#
# Note: Add new test APIs to this server
#

writeUnknownRequest = (res) -> res.writeHead 404

respondToGETRequest = (req, res) ->
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
      res.write TEST_IMAGE_DATA
    when '/checkhost'
      expectedHost = "#{HOSTNAME}:#{HTTPPORT}"
      if req.headers.host == expectedHost
        res.writeHead 200, "Content-Type": "text/plain"
      else
        res.writeHead 500, "Content-Type": "text/plain"
        res.write("host should be #{expectedHost}")
      res.end('\n')
    else
      writeUnknownRequest res
  res.end()

respondToPOSTRequest = (req, res) ->
  switch req.url
    when '/posttest'
      body = JSON.parse(req.body)
      if body.test == 'posttest'
        res.writeHead 200, "Content-Type": "application/json"
        res.write JSON.stringify({ posttest: true })
      else
        res.writeHead 422, "Unprocessable Entity", "Content-Type": "text/plain"
    else
      writeUnknownRequest res
  res.end()

respond = (req, res) ->
  switch req.method
    when 'GET'
      # Respond immediately
      respondToGETRequest(req, res)
    when 'POST'
      # Collect the body
      req.body = ''
      req.on 'data', (chunk) -> req.body += chunk
      req.on 'end', -> respondToPOSTRequest(req, res)
    else
      writeUnknownRequest res
      res.end()

http.createServer((req, res) ->
  if req.method == 'GET' and req.url == '/secure'
    # Redirect to HTTPS if HTTP request to a secure URL
    res.writeHead 302, "Location": "https://#{HOSTNAME}:#{HTTPSPORT}#{req.url}"
    res.end()
  else
    respond req, res
).listen HTTPPORT, HOSTNAME

#
# Create an HTTPS server to test redirects
#

sslOptions =
  'key': fs.readFileSync(__dirname + '/SSL/privatekey.pem')
  'cert': fs.readFileSync(__dirname + '/SSL/certificate.pem')
https.createServer(sslOptions, (req, res) ->
  if req.method == 'GET' and req.url == '/secure'
    # Return 'secure' data if requested over HTTPS
    res.writeHead 200, "Content-Type": "application/json"
    res.write JSON.stringify({ secure: true })
    res.end()
  else
    respond req, res
).listen HTTPSPORT, HOSTNAME

#
# Recording Proxy Server
# Captures requests to Target HTTP Server (above)
#

recordingProxyOptions =
  port: PROXYPORT                     # port to listen on
  fixtures: 'test/fixtures'           # directory where the fixture files are
  target: "#{HOSTNAME}:#{HTTPPORT}"   # target server to proxy
createRecordingProxyServer recordingProxyOptions

#
# Playback Server
# Loads requests captured by Recording Proxy
#

playbackServerOptions =
  port: PLAYBACKPORT          # port to listen on
  fixtures: 'test/fixtures'   # directory where the fixture files are
  hideUnknownRequests: true   # do not show them on screen during testing
createPlaybackServer playbackServerOptions

#
# Test Macros
#

getRawRequest = (port, path, callback, encoding) ->
  options = requestOptions(HOSTNAME, port, path)
  http.request(options, responseWrapper(callback, encoding)).end()
  return

getRequest = (port, path, callback) -> getRawRequest(port, path, callback, 'utf8')
getImageRequest = (port, path, callback) -> getRawRequest(port, path, callback)
postRequest = (port, path, params, callback) ->
  {options, body} = postJSONOptions HOSTNAME, port, path, params
  req = http.request options, responseWrapper(callback, 'utf8')
  req.write body
  req.end()
  return


testRequest = (topic, statusCode = 200, vows = {}) ->
  test = { topic }
  test["should respond with HTTP #{statusCode}"] = (error, results) -> 
    assert.isNull error, "Request had an error #{error}"
    if results.statusCode != statusCode
      assert.isTrue false, "Received statusCode (#{results.statusCode}) expected (#{statusCode})\n#{results.body}"
  _(test).extend vows

testGET = (port, path, statusCode, vows) ->
  topic = -> getRequest port, path, @callback
  testRequest topic, statusCode, vows
testImage = (port, path, statusCode, vows) ->
  topic = -> getImageRequest port, path, @callback
  testRequest topic, statusCode, vows
testPOST = (port, path, params, statusCode, vows = {}) ->
  topic = -> postRequest port, path, params, @callback
  testRequest topic, statusCode, vows


#
# Parameterized tests
# We run the same tests on different ports to make sure that the proxy
# and playback return the original results from the target server
#

testGETUnknown = (port) -> testGET port, '/does-not-exist', 404
testGETText = (port) -> 
  testGET port, '/texttest', 200,
    'should have text data': (results) ->
      assert.equal results.headers['content-type'], "text/plain"
      assert.equal results.body, 'texttest'    
testGETJSON = (port) -> 
  testGET port, '/jsontest', 200,
    'should respond with JSON data': (results) ->
      assert.equal results.headers['content-type'], "application/json"
      assert.deepEqual JSON.parse(results.body), { jsontest: true }
testGETImage = (port) ->
  testImage port, '/imagetest', 200,
    'should respond with image data': (results) ->
      assert.equal results.headers['content-type'], "image/png"
    'should have the same binary image sent by the server': (results) ->
      if results.body.toString('base64') != TEST_IMAGE_DATA.toString('base64')
        assert.isTrue false, "Image received (#{results.body.length} bytes) is not the same as file (#{TEST_IMAGE_DATA.length} bytes)"
testPOSTUnknown = (port) -> testPOST port, '/does-not-exist', {}, 404
testPOSTJSON = (port) -> 
  testPOST port, '/posttest', { test: 'posttest' }, 200,
    'should respond with JSON': (results) ->
      assert.equal results.headers['content-type'], "application/json"
      assert.deepEqual JSON.parse(results.body), { posttest: true }


#
# Parameterized Batch
#
# A suite of the same tests are run against all servers to make sure
# the same resutls are returned
#

createTestBatch = (name, port) ->
  test = {}
  test["Getting an unknown page from the #{name} server"] = testGETUnknown port
  test["Getting text the #{name} server"] = testGETText port
  test["Getting JSON from the #{name} server"] = testGETJSON port
  test["Getting an image from the #{name} server"] = testGETImage port
  test["Posting to an unknown page on the #{name} server"] = testPOSTUnknown port
  test["Posting JSON to the #{name} server"] = testPOSTJSON port
  test

#
# Test Suite
#

vows.describe('Mock HTTP Server Test (mock-http-server-test)')
  #
  # Check if all servers have started
  #
  .addBatch
    'The Target HTTP Server': testHTTPRunning "ERROR: could not connect to Target HTTP Server", HTTPPORT
  .addBatch
    'The Recording Proxy Server': testHTTPRunning "ERROR: could not connect to Recording Proxy Server", PROXYPORT
  .addBatch
    'The playback Server': testHTTPRunning "ERROR: could not connect to the Playback Server", PLAYBACKPORT

  #
  # Verify that the HTTP request suite works
  #

  # [FIRST] Directly on the target
  .addBatch(createTestBatch('target', HTTPPORT))
  # [SECOND] Through the proxy forwarding to the target
  .addBatch(createTestBatch('recording', PROXYPORT))
  # [THIRD] From the playback server
  .addBatch(createTestBatch('playback', PLAYBACKPORT))

  #
  # Additional server-specific tests for edge cases
  #

  .addBatch
    'Getting secure data from the HTTP server': testGET(HTTPPORT, '/secure', 302,
      'should contain a location header': (results) ->
        assert.equal results.headers.location, "https://#{HOSTNAME}:#{HTTPSPORT}/secure"
    )

  .addBatch
    'Verifying the host in the HTTP headers from the proxy': testGET(PROXYPORT, '/checkhost')
    'Getting secure data from the HTTPS server via the proxy': testGET(PROXYPORT, '/secure', 200,
      'should respond with JSON data': (results) ->
        assert.equal results.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(results.body), { secure: true }
    )

  .addBatch
    'Getting an unrecorded page from the playback server': testGET PLAYBACKPORT, '/was-not-recorded', 404
    'Getting secure data from the playback server': testGET(PLAYBACKPORT, '/secure', 200,
      'should respond with JSON data': (results) ->
        assert.equal results.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(results.body), { secure: true }
    )


  .export(module)

