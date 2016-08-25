var exec = require('cordova/exec');
var multipathTCP = {
  download: function(hostname, path, callback, errCallback) {
    exec(callback, errCallback, "MultipathTCP", "download", [hostname, path]);
  }
};

module.exports = multipathTCP;
