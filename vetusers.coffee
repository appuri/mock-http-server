# Run this in the mock-http-server directory

fs = require 'fs'
http = require 'http'
request = require 'request'

# Serialize requests
http.globalAgent.maxSockets = 1

# Get users from file
file = fs.readFileSync('login.txt')
lines = file.toString().split("\n")
users = for line in lines
  line.split(';')[0]

# Make requests to determine userID from user
outstandingRequests = 0
userMap = {}

requestUserInfo = (username) ->
  writeFile = ->
    # Write file every 100 names
    if (outstandingRequests % 100) == 0
      console.log "#{outstandingRequests} users to go"
      fs.writeFileSync('users.json', JSON.stringify(userMap, false, 2))

  requestUserID = (username) ->
    url = "http://mw3-xbox-dev-webzone.demonware.net/mw3/xbox/users/?userName=#{username}&count=100&page=1"
    request url, (error, response, body) ->
      outstandingRequests--
      if response.statusCode == 200 and body        
        userNameQueryInfo = JSON.parse(body)
        userRecord = userNameQueryInfo.data[0]
        if userRecord
          userInfo =
            userName: userRecord.userName
            userID: userRecord.userID
          userMap[username] = userInfo
        else
          console.log "Username #{username} does not have a record"
      else
        console.log "Error with request:"
        console.log " URL: #{url}"
        console.log " statusCode: #{response.statusCode}"
        console.log " body: #{body}"
        console.log " Error: #{error}"
      writeFile()
  outstandingRequests++
  requestUserID(username)

console.log "Starting requests"
for user in users
  requestUserInfo(user) if user.length > 0
