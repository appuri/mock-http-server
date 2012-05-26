# **recording-proxy.coffee**
# Proxy request to the target server and store responses in a file
# specific to the request.
# 

fs          = require 'fs'
path        = require 'path'
crypto      = require 'crypto'
url         = require 'url'
querystring = require 'querystring'
request     = require 'request'
mock        = require '../src/mock-http-server'

exports.RecordingProxy = class RecordingProxy
  constructor: (@options = {}) ->
    @target = options.target
    if not @target.match(/^http/i)
      @target = "http://" + @target

    # Set up directory
    fixtureDir = options.fixtures || 'fixtures'
    @fixturePath = "#{__dirname}/../#{fixtureDir}"
    fs.mkdirSync @fixturePath unless path.existsSync @fixturePath

  # Called once for each request to the HTTP server.
  proxyRequest: (req, res) ->
    self = @

    sendTargetRequest = ->
      # Outgoing request to target server
      outgoing =
        uri: "#{self.target}#{req.url}"
        method: req.method
        headers: req.headers
        body: req.body
        encoding: null
        jar: false

      # Request will replace the host with the target
      delete outgoing.headers.host

      # Issue request to target
      request outgoing, (error, response, body) ->
        if error
          console.log error
          res.writeHead 500, "Content-Type": "text/plain"
          res.write(error)
          res.write("\n\n")
          res.end()
          return

        # Remove HTTP 1.1 headers for HTTP 1.0
        delete response.headers["transfer-encoding"] if req.httpVersion == "1.0"

        # Save recorded data to file
        filepath = "#{self.fixturePath}/#{req.filename}"
        recordingData =
          filepath: req.filename
          method: req.method
          target: self.target
          uri: outgoing.uri
          statusCode: response.statusCode
          headers: response.headers
        recordingData.body64 = response.body.toString('base64') if response.body

        recordingJSON = JSON.stringify(recordingData, true, 2)
        fs.writeFile filepath, recordingJSON, (err) ->
          # Respond after file is written
          if err
            console.log "Error writing request #{req.method} #{req.url} to #{filepath}"
            console.log err
          res.writeHead response.statusCode, response.headers
          res.write body if body
          res.end()

    # When receiving data from the client, save the
    # request body from the client so that we can reissue
    # the request and calculate
    # the hash of the request body and write the chunk
    # to the request of the target.
    req.on "data", (chunk) ->
      req.chunks ||= []
      req.chunks.push chunk
      req.bodyHash ||= crypto.createHash 'sha1'
      req.bodyHash.update chunk

    req.on "end", ->
      # Calculate filename once the request is finished.
      bodyHash = req.bodyHash?.digest('hex')
      req.filename = mock._generateResponseFilename(req.method, req.url, bodyHash)

      # Form complete body to send to target
      if req.chunks
        totalLength = 0
        for chunk in req.chunks
          totalLength += chunk.length
        req.body = new Buffer(totalLength)
        offset = 0
        for chunk in req.chunks
          chunk.copy(req.body, offset)
          offset += chunk.length
        delete req.chunks
      sendTargetRequest()

