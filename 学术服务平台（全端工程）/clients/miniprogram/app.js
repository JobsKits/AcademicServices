const { Client } = require("./utils/api");
App({
  onLaunch() {
    this.api = new Client(wx);
  },
});
