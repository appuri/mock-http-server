module.exports = function(requestSimulator) {
  requestSimulator.register( '/product/:id/user/:username', 'test/simulator/request.template', 'GET', function(data, callback) {
    if (data.id == 15 || data.id == 300) 
      data.productName = "bacon"
    else
      data.productName = "unknown product " + data.id

    var users = {user1: 1234, user2: 1223}
    data.user_id = users[data.username] || -1

    callback(data)
  });
}
