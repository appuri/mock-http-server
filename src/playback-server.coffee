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
    @fixturesPath = mock._generateFixturesPath(options.fixtures)

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
      bodyHash = req.bodyHash?.digest('hex')
      { filename, FILEVERSION } = mock._generateResponseFilename(req, bodyHash)
      @_playbackResponseFromFilename req, res, filename, FILEVERSION

  # When a response has not been recorded, this
  # method will log that to the console and
  # return a 404 (Not Found)
  _respondWithNotFound: (req, res, filename) ->
    unless @options.hideUnknownRequests
      unless @notfound[filename]
        if _.isEmpty(@notfound)
          console.log "Unrecorded requests:"
          console.log " Fixtures Path: #{@fixturesPath}"
        @notfound[filename] = true
        # Debug data
        console.log " Method: #{req.method}"
        console.log " Host: #{req.headers?.host || 'localhost'}"
        console.log " Path: #{req.url}"
        console.log " Filename: #{filename}"
    res.writeHead 404
    res.end()

  # Send the recorded response to the client
  # The recorded response has the request body
  # in the original chunks sent from the client
  # encoded into base64 for serialization
  _playbackRecordedResponse: (req, res, recordedResponse) ->
    { statusCode, headers, body } = recordedResponse
    res.writeHead statusCode, headers
    res.write(body) if body
    res.end()

  # Check if file exists and if so parse and send it.
  _playbackResponseFromFile: (req, res, filename, minimumFileversion) ->
    filepath = "#{@fixturesPath}/#{filename}"
    path.exists filepath, (exists) =>
      if exists
        fs.readFile filepath, (err, data) =>
          try
            throw err if err
            recordedResponse = JSON.parse data
            actualFileversion = recordedResponse.fileversion || 0
            if actualFileversion < minimumFileversion
              throw "Fixture file version was #{actualFileversion} expecting #{minimumFileversion}.  Update server with latest code."
            if recordedResponse.body64
              recordedResponse.body = new Buffer(recordedResponse.body64, 'base64')
              delete recordedResponse.body64
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
  _playbackResponseFromFilename: (req, res, filename, fileversion) ->
    if @notfound[filename]
      # We've already had this request but do not have a recorded response
      @_respondWithNotFound req, res, filename
    else
      # Get file contents out of cache unless options have it turned off
      recordedResponse = @responses[filename]
      if recordedResponse
        @_playbackRecordedResponse req, res, recordedResponse
      else
        @_playbackResponseFromFile req, res, filename, fileversion

