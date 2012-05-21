events      = require 'events'
http        = require 'http'
fs          = require 'fs'
path        = require 'path'
crypto      = require 'crypto'
{_}         = require 'underscore'
mock        = require '../lib/mock-http-server'

exports.PlaybackServer = class PlaybackServer extends events.EventEmitter

  constructor: (@options = {}) ->
    @responses = {}
    @notfound = {}
    fixtureDir = options.fixtures || 'fixtures'
    @fixturePath = "#{__dirname}/../#{fixtureDir}"

  playbackRequest: (req, res) ->
    req.on "data", (chunk) ->
      req.bodyHash ||= crypto.createHash 'sha1'
      req.bodyHash.update chunk

    req.on "end", =>
      filename = mock._generateResponseFilename(req.method, req.url, req.bodyHash?.digest('hex'))
      @_playbackResponseFromFilename req, res, filename

  close: -> undefined


  _respondWithNotFound: (req, res, filename) ->
    if @options.logUnknownRequests
      unless @notfound[filename]
        if _.isEmpty(@notfound)
          console.log "Unrecorded requests:"
        @notfound[filename] = true
        console.log " #{req.method} #{req.url}"
    res.writeHead 404
    res.end()

  _playbackRecordedResponse: (req, res, recordedResponse) ->
    { statusCode, headers, data, body } = recordedResponse
    if not body and data.length > 0 
      debugger;
      # Create body from base64 encoded data chunks
      chunks = []
      while not _.isEmpty(data)
        base64chunk = data.shift()
        chunks.push(new Buffer(base64chunk, 'base64'))

      totalLength = 0
      for chunk in chunks
        totalLength += chunk.length
      body = new Buffer(totalLength)
      offset = 0
      for chunk in chunks
        chunk.copy(body, offset)
        offset += chunk.length
      recordedResponse.body = body

    res.writeHead statusCode, headers
    res.write(body) if body
    res.end()

  _playbackResponseFromFile: (req, res, filename) ->
    filepath = "#{@fixturePath}/#{filename}"
    path.exists filepath, (exists) =>
      if exists
        fs.readFile filepath, (err, data) =>
          try
            throw err if err
            recordedResponse = JSON.parse data
            @responses[filename] = recordedResponse
            @_playbackRecordedResponse req, res, recordedResponse
          catch e
            console.log "Error loading #{filename}: #{e}"
            res.writeHead 500
            res.end()
      else
        @_respondWithNotFound req, res, filename

  _playbackResponseFromFilename: (req, res, filename) ->
    if @notfound[filename]
      # We've already had this request but do not have a recorded response
      @_respondWithNotFound req, res, filename
    else
      # Get file contents out of cache unless options have it turned off
      recordedResponse = @responses[filename] unless @options.alwaysLoadFixtures
      if recordedResponse
        @_playbackRecordedResponse req, res, recordedResponse
      else
        @_playbackResponseFromFile req, res, filename

