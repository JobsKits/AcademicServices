const { Client } = require("./Utils/api");
App({
  onLaunch() {
    this.api = new Client(wx);
  },
});
