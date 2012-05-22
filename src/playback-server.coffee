# **playback-server.coffee**
# Playback requests recorded into fixtures directory.
# 

events      = require 'events'
http        = require 'http'
fs          = require 'fs'
path        = require 'path'
crypto      = require 'crypto'
{_}         = require 'underscore'
mock        = require '../src/mock-http-server'

exports.PlaybackServer = class PlaybackServer extends events.EventEmitter

  constructor: (@options = {}) ->
    # Store responses keyed by filename
    @responses = {}
    # Store previous requests that were not recorded
    @notfound = {}
    # Directory to store fixtures
    fixtureDir = options.fixtures || 'fixtures'
    @fixturePath = "#{__dirname}/../#{fixtureDir}"

  # Called once for each request that comes into the HTTP server.
  playbackRequest: (req, res) ->

    # Set event handlers to calculate sha1 hash of body while it is
    # being sent from the client.
    # The Playback Server ignores the request, but the hash
    # is used to differentiate post requests to the same endpoint
    req.on "data", (chunk) ->
      req.bodyHash ||= crypto.createHash 'sha1'
      req.bodyHash.update chunk

    # Event emitted once the entire request has been received.
    # Calculate a unique filename for this request and
    # send the response from the file
    req.on "end", =>
      filename = mock._generateResponseFilename(req.method, req.url, req.bodyHash?.digest('hex'))
      @_playbackResponseFromFilename req, res, filename

  close: -> undefined


  # When a response has not been recorded, this
  # method will log that to the console and
  # return a 404 (Not Found)
  _respondWithNotFound: (req, res, filename) ->
    unless @options.hideUnknownRequests
      unless @notfound[filename]
        if _.isEmpty(@notfound)
          console.log "Unrecorded requests:"
        @notfound[filename] = true
        console.log " #{req.method} #{req.url}"
    res.writeHead 404
    res.end()

  # Send the recorded response to the client
  # The recorded response has the request body
  # in the original chunks sent from the client
  # encoded into base64 for serialization
  _playbackRecordedResponse: (req, res, recordedResponse) ->
    { statusCode, headers, data, body } = recordedResponse
    if not body and data.length > 0 
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

  # Check if file exists and if so parse and send it.
  _playbackResponseFromFile: (req, res, filename) ->
    filepath = "#{@fixturePath}/#{filename}"
    path.exists filepath, (exists) =>
      if exists
        fs.readFile filepath, (err, data) =>
          try
            throw err if err
            recordedResponse = JSON.parse data
            @responses[filename] = recordedResponse unless @options.alwaysLoadFixtures
            @_playbackRecordedResponse req, res, recordedResponse
          catch e
            console.log "Error loading #{filename}: #{e}"
            res.writeHead 500
            res.end()
      else
        @_respondWithNotFound req, res, filename

  # Determines if request is not recorded or in the cache
  # before loading it from a file.
  _playbackResponseFromFilename: (req, res, filename) ->
    if @notfound[filename]
      # We've already had this request but do not have a recorded response
      @_respondWithNotFound req, res, filename
    else
      # Get file contents out of cache unless options have it turned off
      recordedResponse = @responses[filename]
      if recordedResponse
        @_playbackRecordedResponse req, res, recordedResponse
      else
        @_playbackResponseFromFile req, res, filename

