events      = require 'events'
http        = require 'http'
crypto      = require 'crypto'
querystring = require 'querystring'
mock        = require '../lib/mock-http-server'

exports.RecordingProxy = class RecordingProxy extends events.EventEmitter
  constructor: (options = {}) ->
    # Set up events
    events.EventEmitter.call(@)

    # Set up target information
    @target = options.target
    unless @target?.host and options.target?.port
      throw new Error("options must contain target.host and target.port")
    @target.agent = mock._getAgent(@target)
    @target.protocol = mock._getProtocol(@target)
    @target.base = mock._getBase(@target)

  proxyRequest: (req, res) ->
    self      = @
    outgoing  = new(@target.base)
    errState  = false

    @emit 'start', req, res

    #
    # Outgoing request to target
    #

    outgoing.host = @target.host
    outgoing.port = @target.port
    outgoing.agent = @target.agent
    outgoing.method = req.method
    outgoing.path = req.url
    outgoing.headers = req.headers

    reverseProxy = @target.protocol.request outgoing, (response) ->
      # Match header connection between source and target responses
      if response.headers.connection
        if req.headers.connection
          response.headers.connection = req.headers.connection
        else
          response.headers.connection = "close"

      # Remove HTTP 1.1 headers
      delete response.headers["transfer-encoding"] if req.httpVersion == "1.0"

      # Replace redirect scheme if we are targeting an HTTPS server
      if (response.statusCode == 301) || (response.statusCode == 302)
        if self.target.https
          response.headers.location = response.headers.location.replace(/^https\:/, "http:")

      # Start writing response to source
      res.writeHead response.statusCode, response.headers
      if response.statusCode == 304
        try
          res.end()
        catch ex
          console.error "res.end error: %s", ex.message
        return

      # Manage stream events from target response
      ended = false
      onData = (chunk) ->
        # Back off if throughput too high
        if res.writable
          if res.write(chunk) == false and response.pause
            response.pause()

      onDrain = ->
        # Resume when queue drained
        if response.readable and response.resume
          response.resume()

      onClose = -> response.emit 'end' unless ended

      onEnd = ->
        ended = true
        unless errState
          reverseProxy.removeListener "error", proxyError
          try
            res.end()
            console.log ">>> recording-proxy.coffee:84 ENDED", req.filename
          catch ex
            console.error "res.end error: %s", ex.message
          self.emit "end", req, res

      res.on 'drain', onDrain
      response.on 'data', onData
      response.on 'close', onClose
      response.on "end", onEnd    

    proxyError = (err) ->
      errState = true
      return if self.emit("proxyError", err, req, res)
      res.writeHead 500, "Content-Type": "text/plain"

      if req.method isnt "HEAD"
        if process.env.NODE_ENV is "production"
          res.write "Internal Server Error"
        else
          res.write "An error has occurred: " + JSON.stringify(err)
      try
        res.end()
      catch ex
        console.error "res.end error: %s", ex.message
    reverseProxy.once "error", proxyError

    req.on "aborted", -> reverseProxy.abort()

    req.on "data", (chunk) ->
      unless errState
        req.bodyHash ||= crypto.createHash 'sha1'
        req.bodyHash.update chunk
        flushed = reverseProxy.write(chunk)
        if not flushed
          req.pause()
          reverseProxy.once "drain", ->
            try
              req.resume()
            catch er
              console.error "req.resume error: %s", er.message
          setTimeout (-> reverseProxy.emit "drain"), 100

    req.on "end", ->
      req.filename = mock._generateFilename(req.method, req.url, req.bodyHash?.digest('hex'))
      reverseProxy.end() unless errState

    req.on "close", ->
      reverseProxy.abort() unless errState

  close: -> @emit 'end'
