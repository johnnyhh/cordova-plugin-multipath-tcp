var exec = require('cordova/exec');
var multipathTCP = {
  request: function(method, downloadUrl, callback, errCallback) {
    function onSuccess() {
      var code = arguments[0];
      var headers = arguments[1];
      var body = arguments[2];
      callback(code, headers, body);
    }
    exec(onSuccess, errCallback, "MultipathTCP", "request", [method, downloadUrl]);

    return {
      onProgress: function(callback, errCallback) {
        exec(callback, errCallback, "MultipathTCP", "onRequestProgress", []);
      }
    };
  },
};

module.exports = multipathTCP;
