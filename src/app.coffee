# **app.coffee**
# Script that is used to create `./bin/mock-http-server`.
#

http    = require 'http'
url     = require 'url'
{argv}  = require 'optimist'
{_}     = require 'underscore'
mock    = require '../src/mock-http-server'
cluster = require 'cluster'
os      = require 'os'

numCPUs = os.cpus().length

{createRecordingProxyServer, createPlaybackServer} = mock


DEFAULT_FIXTURES = 'fixtures'

help = ->
  exe = 'mock-http-server'
  msg = 
    """
    Usage: #{exe} port [options]

      Where port is to listen on for incoming requests.
      Port can either be a stand-alone port and #{exe}
      will listen on IPADDR_ANY or a host:port pair and
      #{exe} will be bound to the host.
    
    Options:
    
      --record
           Record results (use Host field in HTTP header)
      --record=http://host:port
           Record results to host:port
      --fixtures=directory
           store files relative to cwd (default ./#{DEFAULT_FIXTURES})
      --simulator=file
           request simulator script
      --latency
           Simulate latency in playback mode
    
    
    Usage:
    
      When the recording proxy is being run as a stand-alone server
      and the clients are setting the Host field in the header to the
      remote servers, then you can run the mock recording proxy:
    
        #{exe} 9000 --record
    
        curl -H 'Host: www.google.com' 'http://localhost:9000/'
        curl -H 'Host: www.apple.com' 'http://localhost:9000/'
    
      When the proxy is running on localhost and you want all traffic
      to be sent to a specific remote server, then add a target in the
      record flag:
    
        #{exe} 9000 --record=www.google.com
    
        curl 'http://localhost:9000/'
    
      To play back results, leave off the --record flag:
    
        #{exe} 9000

        (assuming that you've recorded these requests above)    
        curl -H 'Host: www.google.com' 'http://localhost:9000/'
        curl -H 'Host: www.apple.com' 'http://localhost:9000/'
        curl 'http://localhost:9000/'
    """
  console.log msg

if argv.help or argv._.length < 1
  help()
  process.exit 1

bind = '0.0.0.0'
ipport = argv._[0]
if ipport.toString().match(/:/)
  ipport = ipport.split(':')
  bind = ipport[0]
  port = parseInt(ipport[1])
else
  port = parseInt(ipport)


if not port? || port == 0
  console.log "Error: must specify a port"
  help()
  process.exit 1

fixtures = argv.fixtures || DEFAULT_FIXTURES
simulator = argv.simulator
record = argv.record
latencyEnabled = argv.latency

options = { bind, port, fixtures, simulator, latencyEnabled }
if record?
  console.log "Running in recording mode"
  if record == true
    # NO target set (use host in request header)
    console.log "  Recording calls to host in request header"
  else
    # A specfic target was set in the options
    options.target = record
    console.log "  Recording calls to " + options.target
  # See recording-proxy.coffee
  createRecordingProxyServer options
else
  console.log "Running in playback mode"
  # See playback-server.coffee
  if cluster.isMaster
    # Fork workers.
    i = 0
    while i < numCPUs
      cluster.fork()
      i++
  else
    # Workers can share any TCP connection
    # In this case its a HTTP server
    createPlaybackServer options

console.log "  Fixtures directory: #{fixtures}"
console.log "  Listening at http://#{bind}:#{port}/"
