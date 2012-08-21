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
http        = require 'http'

http.globalAgent.maxSockets = 1

RETRY_TIMEOUT     = 30000 # Time in seconds before responding to original request
RETRY_MAX_BACKOFF = 3000  # Max time in seconds to randomize request retry

exports.RecordingProxy = class RecordingProxy
  constructor: (@options = {}) ->
    @target = options.target
    @retryTimeout = @options.retryTimeout || RETRY_TIMEOUT
    @retryMaxBackoff = @options.retryMaxBackoff || RETRY_MAX_BACKOFF

    # Set up directory
    @fixturesPath = mock._generateFixturesPath(options.fixtures)
    fs.mkdirSync @fixturesPath unless fs.existsSync @fixturesPath

  # Called once for each request to the HTTP server.
  proxyRequest: (req, res) ->
    self = @

    sendTargetRequest = ->
      filepath = "#{self.fixturesPath}/#{req.filename}"

      logErrorToConsole = (error) ->
        unless self.options.quietMode
          console.error "Error with request #{req.method} #{req.url} to #{filepath}"
          console.error error
        res.writeHead 500, "Content-Type": "text/plain"
        res.write error.toString()
        res.end()

      isLocalHost = (host) -> host? && (host.match(/localhost/) || host.match('127.0.0.1') || host.match('::1'))

      validateTarget = ->
        target = null
        if self.target
          target = self.target
        else if req.headers?.host
          if isLocalHost(req.headers.host)
            logErrorToConsole "localhost used without --record=target"
          else
            target = req.headers.host
        else
          logErrorToConsole "no host in request"

        if target and not target.match(/^http/i)
          target = "http://" + target
        target


      target = validateTarget req
      return unless target

      validateRequestPath = ->
        requestPath = url.parse(req.url)
        path = requestPath.path
        path += requestPath.hash if requestPath.hash
        path

      outgoing =
        uri: "#{target}#{validateRequestPath(req.url)}"
        method: req.method
        headers: req.headers
        body: req.body
        encoding: null
        jar: false
        firstSentAt: (new Date()).getTime()

      delete outgoing.headers.host if isLocalHost(outgoing.headers?.host)
      delete outgoing.headers['Connection']
      delete outgoing.headers['connection']

      # Issue request to target
      sendOutgoingRequest = ->
        outgoing.sentAt = (new Date()).getTime()
        request outgoing, (error, response, body) ->
          if error
            resendOutgoingRequest = ->
              timeNow = (new Date()).getTime()
              randomDelay = Math.random() * self.retryMaxBackoff
              retryTime = timeNow - outgoing.firstSentAt + randomDelay
              timedOut = retryTime > self.retryTimeout
              return false if timedOut
              setTimeout(sendOutgoingRequest, randomDelay)
              return true

            if (error.code == 'ECONNRESET' or error.code == 'HPE_INVALID_CONSTANT') and resendOutgoingRequest()
              return # the request will be reissued after a delay
            else
              unless self.options.quietMode
                console.error "HTTP Error"
                console.error outgoing
                console.error "response"
                console.error response
                console.error "body"
                console.error body
              return logErrorToConsole(error)

          # Remove HTTP 1.1 headers for HTTP 1.0
          delete response.headers["transfer-encoding"] if req.httpVersion == "1.0"

          # Save recorded data to file
          recordingData =
            filepath: req.filename
            fileversion: req.fileversion
            method: req.method
            target: target
            uri: outgoing.uri
            statusCode: response.statusCode
            headers: response.headers
            host: outgoing?.headers?.host
            latency: (new Date()).getTime() - outgoing.sentAt
          recordingData.body64 = response.body.toString('base64') if response.body

          recordingJSON = JSON.stringify(recordingData, true, 2)
          fs.writeFile filepath, recordingJSON, (error) ->
            return logErrorToConsole(error) if error
            res.writeHead response.statusCode, response.headers
            res.write(body) if body
            res.end()
      sendOutgoingRequest()

    # When receiving data from the client, save the
    # request body from the client so that we can reissue
    # the request and calculate
    # the hash of the request body and write the chunk
    # to the request of the target.
    req.on "data", (chunk) ->
      req.chunks ||= []
      req.chunks.push chunk

    req.on "end", ->
      # Form complete body to send to target
      bodyHash = null
      if req.chunks
        bodyHash = crypto.createHash 'sha1'
        totalLength = 0
        for chunk in req.chunks
          totalLength += chunk.length
        req.body = new Buffer(totalLength)
        offset = 0
        for chunk in req.chunks
          bodyHash.update chunk
          chunk.copy(req.body, offset)
          offset += chunk.length
        delete req.chunks
        bodyHash = bodyHash.digest('hex')
      # Calculate filename once the request is finished.
      { filename, FILEVERSION } = mock._generateResponseFilename(req, bodyHash)
      req.filename = filename
      req.fileversion = FILEVERSION
      sendTargetRequest()

