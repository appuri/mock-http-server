#
# This test suite starts HTTP and HTTPS servers, a recording proxy
# and a playback server.
# 
# The test batches mostly test that the same requests return from
# each server.
#
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
net       = require 'net'

{responseWrapper, testHTTPRunning, requestOptions, postJSONOptions, serialTest, sendRawHttpRequest} = helpers
{createRecordingProxyServer, createPlaybackServer} = mock

HOSTNAME        = '127.0.0.1'
HTTPPORT        = 7771  # Target HTTP server
PROXYPORT       = 7772  # Recording Proxy Server
PLAYBACKPORT    = 7773  # Playback HTTP server
HTTPSPORT       = 7774  # Target HTTPS server
THROTTLEPORT    = 7775  # Proxy that is being throttled
ECONNRESETPORT  = 7776  # Raw TCP port that does an ECONNRESET to throttle requests
PLAYBACKPORT2   = 7777  # Playback HTTP server with simulated requests

#
# Binary data used for testing large HTTP response bodies
#

createBinaryImageData = (size, offset = 0, mod = 256)->
  data = new Buffer(size)
  i = 0
  while i < size
    val = (i % mod) + offset
    data.writeUInt8(val, i)
    i++
  data

TEST_IMAGE_DATA = createBinaryImageData(1 * 1024 * 1024)
TEST_LARGE_PATH = "/large?data=" + createBinaryImageData(1024, 65, 26).toString('ascii')

#
# A simple HTTP server that is used as the target
# for the recording proxy
#
# Note: Add new test APIs to this server
#

writeUnknownRequest = (res) -> res.writeHead 404

respondToGETRequest = (req, res) ->
  [path, query] = req.url.split('?')
  switch path
    when '/'
      res.writeHead 200, "Content-Type": "text/plain"
    when '/texttest'
      res.writeHead 200, "Content-Type": "text/plain"
      res.write "texttest"
    when '/jsontest'
      assert.equal query, "param=test"
      res.writeHead 200, "Content-Type": "application/json"
      res.write JSON.stringify({ jsontest: true })
    when '/imagetest'
      res.writeHead 200, "Content-Type": "image/png"
      res.write TEST_IMAGE_DATA
    when '/not-modified'
      res.writeHead 304
    when '/infiniteloop'
      res.writeHead 302, "Location": "http://#{req.headers.host}#{req.url}"
    when '/server-error'
      res.writeHead 500, "Content-Type": "text/plain"
      res.write "Server Error Test"
    when '/large'
      assert.equal req.url, TEST_LARGE_PATH
      res.writeHead 200, "Content-Type": "text/plain"
    when '/1secdelay'
      res.keepOpen = true
      delay = ->
        res.writeHead 200, "Content-Type": "application/json"
        res.write JSON.stringify({ delay: true })
        res.end()
      setTimeout(delay, 1000)
    when '/checkhost'
      hostname = req.headers.host.split(':')[0]
      res.writeHead 200, "Content-Type": "text/plain"
      res.write hostname
    when '/invalid-response'
      res.socket.end('not a valid HTTP response on the response socket')
    when '/expires'
      headers =
        "Content-Type": "text/plain",
        "Expires": (new Date(Date.now() + 60000))
      res.writeHead 200, headers
    else
      writeUnknownRequest res
  res.end() unless res.keepOpen

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
# Throttling server
# This server mimics an HTTP server that throttles requests
# by resetting the socket connection via ECONNRESET
#
createThrottlingServer = (countdown) ->
  throttleHandler = (socket) ->
    if --countdown > 0
      socket.destroy()
    socket.end("HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 5\r\n\r\nhello", 'utf8')
  net.createServer(throttleHandler).listen(ECONNRESETPORT)
createThrottlingServer(9)

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
  quietMode: true
  retryTimeout: 1000
  retryMaxBackoff: 100
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
# Playback Server with simulated requests
# Serves requests captured by Recording Proxy along with rule based simulated requests
#

playbackServerWithSimulatedRequestsOptions =
  port: PLAYBACKPORT2         # port to listen on
  fixtures: 'test/fixtures'   # directory where the fixture files are
  simulator:'test/simulator/test.js'   # test simulator script
  hideUnknownRequests: true   # do not show them on screen during testing
createPlaybackServer playbackServerWithSimulatedRequestsOptions

#
# Throttled Proxy Server
# Tests proxying to a service that does throttling via ECONNRESET
#

throttlingProxyOptions =
  port: THROTTLEPORT                  # port to listen on
  fixtures: 'test/fixtures'           # directory where the fixture files are
  target: "#{HOSTNAME}:#{ECONNRESETPORT}"   # target will throttle requests
  quietMode: true
  retryTimeout: 1000
  retryMaxBackoff: 100
createRecordingProxyServer throttlingProxyOptions

#
# Test Macros
#

getRawRequest = (port, path, callback, encoding, opts) ->
  options = requestOptions(HOSTNAME, port, path)
  _.extend(options, opts) if opts
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
testMGET = (port, path, requests, options, vows) ->
  test = {
    topic: ->
      callback = @callback
      error = null
      results = []
      outstandingRequests = 0
      countdownLatch = (err, res) ->
        if err
          error = err
        else if res.statusCode != 200
          error = "Expected status code 200 but received #{res.statusCode}"
        results.push(res) if res
        if --outstandingRequests == 0
          callback(error, results)
      addOutstandingRequest = ->
        outstandingRequests++
        getRawRequest port, path, countdownLatch, 'utf8', options
      i = 0
      while i < requests
        addOutstandingRequest()
        i++
      return
  }
  _(test).extend vows



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
  testGET port, '/jsontest?param=test', 200,
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
testGETNotModified = (port) -> testGET port, '/not-modified', 304
testGETServerError = (port) -> testGET port, '/server-error', 500
testPOSTUnknown = (port) -> testPOST port, '/does-not-exist', {}, 404
testPOSTJSON = (port) -> 
  testPOST port, '/posttest', { test: 'posttest' }, 200,
    'should respond with JSON': (results) ->
      assert.equal results.headers['content-type'], "application/json"
      assert.deepEqual JSON.parse(results.body), { posttest: true }

testGEThost = (port) ->
  return {
    topic: ->
      callback = @callback
      serialTest
        firsthost: ->
          options = requestOptions(HOSTNAME, port, '/checkhost')
          options.headers =
            'Host': 'firsthost'
          http.request(options, responseWrapper(this)).end()
        secondhost: ->
          options = requestOptions(HOSTNAME, port, '/checkhost')
          options.headers =
            'Host': 'secondhost'
          http.request(options, responseWrapper(this)).end()
        end: (results) -> callback null, results
        catch: (err) -> throw err
      return
    'should return results for the first host': ({firsthost}) ->
      assert.equal firsthost.body.toString('utf8'), 'firsthost'
    'should return results for the second host': ({secondhost}) ->
      assert.equal secondhost.body.toString('utf8'), 'secondhost'
  }

testGETExpires = (port) -> 
  testGET port, '/expires', 200,
    'should have expires header': (results) ->
      assert.isTrue results.headers['expires']?

testProxyHost = (port) ->
  return {
    topic: ->
      callback = @callback
      host = 'www.test.host.abc'
      path = '/hosttest'
      sendRawHttpRequest({port, host, path}, callback)
      return
    'view results': (results...) -> console.log ">>> results", results...
    'should return status OK': ({statusCode}) ->
      assert.equal statusCode, 200
    'should return host in response': ({response}) ->
      match = response.match(/Host: (.*)\r\n/gm)
      assert.isTrue match?, "match should be valid"
      assert.equal match[1], host
  }

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
  test["Getting a URL that is not modified from the #{name} server"] = testGETNotModified port
  test["Getting a URL that results in a error from the #{name} server"] = testGETServerError port
  test["Getting the same path from different hosts on #{name} server"] = testGEThost port
  test["Getting a large path the #{name} server"] = testGET port, TEST_LARGE_PATH, 200
  test["Posting to an unknown page on the #{name} server"] = testPOSTUnknown port
  test["Posting JSON to the #{name} server"] = testPOSTJSON port
  test["Getting an expires header from the #{name} server"] = testGETExpires port
  test["Using the hostname in the request to the #{name} server"] = testProxyHost port
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
  .addBatch
    'The playback Server with simulated requests': testHTTPRunning "ERROR: could not connect to the Playback Server with simulated requests", PLAYBACKPORT2

  #
  # Verify that the HTTP request suite works
  #

  # [FIRST] Directly on the target
  .addBatch(createTestBatch('target', HTTPPORT))
  # [SECOND] Through the proxy forwarding to the target
  .addBatch(createTestBatch('recording', PROXYPORT))
  # [THIRD] From the playback server
  .addBatch(createTestBatch('playback', PLAYBACKPORT))
  # [THIRD] From the playback server with simulated requests
  .addBatch(createTestBatch('playback with simulated requests', PLAYBACKPORT2))

  #
  # Additional server-specific tests for edge cases
  #

  #
  # Special tests for direct web server
  #
  .addBatch
    'Getting secure data from the HTTP server': testGET(HTTPPORT, '/secure', 302,
      'should contain a location header': (results) ->
        assert.equal results.headers.location, "https://#{HOSTNAME}:#{HTTPSPORT}/secure"
    )

  #
  # Special tests for the recording proxy
  #
  .addBatch
    'Getting secure data from the HTTPS server via the proxy': testGET(PROXYPORT, '/secure', 200,
      'should respond with JSON data': (results) ->
        assert.equal results.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(results.body), { secure: true }
    )
    'Sending many requests to a server': testMGET(PROXYPORT, '/texttest', 100, {},
      'should return without error': (error, results) ->
        assert.isNull error
        for result in results
          assert.equal result.statusCode, 200
    )
  .addBatch
    'Sending many requests to a server with no connection pooling': testMGET(HTTPPORT, '/texttest', 100, {headers: {'Connection': 'close'}},
      'should return without error': (error, results) ->
        assert.isNull error
        for result in results
          assert.equal result.statusCode, 200
    )
  .addBatch
    'Recording many requests to a server with no connection pooling': testMGET(PROXYPORT, '/texttest', 100, {headers: {'Connection': 'close'}},
      'should return without error': (error, results) ->
        assert.isNull error
        for result in results
          assert.equal result.statusCode, 200
    )

  #
  # Special tests for the playback server
  #
  .addBatch
    'Getting an unrecorded page from the playback server': testGET PLAYBACKPORT, '/was-not-recorded', 404
    'Getting secure data from the playback server': testGET(PLAYBACKPORT, '/secure', 200,
      'should respond with JSON data': (results) ->
        assert.equal results.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(results.body), { secure: true }
    )

  #
  # Special tests for the playback server serving simulated requests
  #
  .addBatch
    'Getting an unrecorded, unsimulated page from the playback server with simulated requests': testGET PLAYBACKPORT2, '/was-not-recorded', 404
    'Getting secure data from the playback server with simulated requests': testGET(PLAYBACKPORT2, '/secure', 200,
      'should respond with JSON data': (results) ->
        assert.equal results.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(results.body), { secure: true }
    )
    'Getting an unrecorded, simulated page from the playback server with simulated requests': testGET(PLAYBACKPORT2, '/product/300/user/user1', 200,
      'should respond with JSON data': (results) ->
        assert.equal results.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(results.body), { product:'bacon', userid: 1234 }
    )
    'Getting another unrecorded, simulated page from the playback server with simulated requests': testGET(PLAYBACKPORT2, '/product/3000/user/user123', 200,
      'should respond with JSON data': (results) ->
        assert.equal results.headers['content-type'], "application/json"
        assert.deepEqual JSON.parse(results.body), { product:'unknown product 3000', userid: -1 }
    )

  #
  # Special tests
  #
  .addBatch
    'Getting an unparseable response will retry and return': testGET PROXYPORT, '/invalid-response', 500
  .addBatch
    'Getting an unparseable response will not be recorded': testGET PLAYBACKPORT, '/invalid-response', 404
  .addBatch
    'Sending a request to a mock throttled server': testGET THROTTLEPORT, '/throttle', 200

  .export(module)

