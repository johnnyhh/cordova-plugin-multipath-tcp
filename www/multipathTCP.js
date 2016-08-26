var exec = require('cordova/exec');
var multipathTCP = {
  download: function(downloadUrl, callback, errCallback) {
    exec(callback, errCallback, "MultipathTCP", "download", [downloadUrl]);
  },
  onDownloadProgress: function(callback, errCallback) {
    exec(callback, errCallback, "MultipathTCP", "onDownloadProgress", []);
  }
};

module.exports = multipathTCP;
