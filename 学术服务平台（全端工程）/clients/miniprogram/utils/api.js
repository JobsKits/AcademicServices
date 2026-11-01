const services = [
  {
    id: "graduation",
    name: "毕业论文",
    summary: "选题与写作辅导",
    description: "选题、结构、方法及格式辅导，交付以确认报价为准。",
    active: true,
  },
  {
    id: "journal",
    name: "普刊",
    summary: "期刊咨询与稿件服务",
    description: "期刊咨询、稿件整理与投稿协助。",
    active: true,
  },
  {
    id: "editing",
    name: "编译",
    summary: "学术翻译与语言润色",
    description: "基于本人稿件提供翻译与语言服务。",
    active: true,
  },
];
function key() {
  return (
    "mini-" +
    Date.now().toString(36) +
    "-" +
    Math.random().toString(36).slice(2)
  );
}
class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}
class Client {
  constructor(wx) {
    this.wx = wx;
    this.base = wx.getStorageSync("apiBase") || "http://127.0.0.1:8080/api/v1";
    this.token = "";
    this.user = null;
    this.mode = "live";
    this.cases = [];
    this.pending = null;
    this.generation = 0;
  }
  configure(base) {
    if (!/^https?:\/\/[^\s]+$/.test(base))
      throw Error("请输入完整HTTP(S)服务地址");
    this.logout();
    this.base = base.replace(/\/$/, "");
    this.wx.setStorageSync("apiBase", this.base);
  }
  logout() {
    this.generation++;
    this.token = "";
    this.user = null;
    this.cases = [];
    this.pending = null;
    this.mode = "live";
  }
  request(path, method = "GET", data, requestKey) {
    const requestGeneration = this.generation;
    return new Promise((resolve, reject) =>
      this.wx.request({
        url: this.base + path,
        method,
        data,
        timeout: 2500,
        header: {
          "Content-Type": "application/json",
          ...(this.token ? { Authorization: "Bearer " + this.token } : {}),
          ...(requestKey ? { "Idempotency-Key": requestKey } : {}),
        },
        success: (r) => {
          if (requestGeneration !== this.generation) {
            reject(new ApiError("账户已变化，请重试", 409));
            return;
          }
          if (r.statusCode === 401) {
            this.logout();
            reject(new ApiError("登录已失效，请重新登录", 401));
            return;
          }
          if (r.statusCode < 200 || r.statusCode >= 300) {
            reject(
              new ApiError(
                (r.data && r.data.error && r.data.error.message) ||
                  "请求未完成",
                r.statusCode,
              ),
            );
            return;
          }
          if (!r.data || typeof r.data !== "object") {
            reject(new ApiError("响应格式异常", 502));
            return;
          }
          resolve(r.data);
        },
        fail: () =>
          reject(
            new ApiError(
              requestGeneration !== this.generation
                ? "账户已变化"
                : "暂时连接不到服务",
              requestGeneration !== this.generation ? 409 : 0,
            ),
          ),
      }),
    );
  }
  async login(account, password, allowDemo = false) {
    this.logout();
    const generation = this.generation;
    try {
      const r = await this.request("/auth/login", "POST", {
        account,
        password,
      });
      if (generation !== this.generation) throw Error("登录状态已变化");
      if (!r.token || !r.user || !r.user.id)
        throw new ApiError("登录响应异常", 502);
      this.token = r.token;
      this.user = r.user;
      this.mode = "live";
      const saved = this.wx.getStorageSync(
        "pending:" + this.base + ":" + this.user.id,
      );
      this.pending = saved && typeof saved.key === "string" ? saved : null;
      return r.user;
    } catch (e) {
      if (allowDemo && (!e.status || e.status >= 500)) {
        this.user = { id: "demo", name: "本地演示", role: "customer" };
        this.mode = "demo";
        return this.user;
      }
      throw e;
    }
  }
  async listServices() {
    try {
      const r = await this.request("/services");
      if (
        !Array.isArray(r.services) ||
        !r.services.every((s) => s.id && s.name)
      )
        throw new ApiError("服务响应异常", 502);
      return { services: r.services, source: "live" };
    } catch (e) {
      if (e.status && e.status < 500) throw e;
      return { services: JSON.parse(JSON.stringify(services)), source: "demo" };
    }
  }
  async workspace() {
    if (!this.user) throw new ApiError("请先登录", 401);
    const generation = this.generation;
    try {
      const r = await this.request("/workspace");
      if (generation !== this.generation) throw Error("账户已变化");
      if (
        !Array.isArray(r.cases) ||
        !r.cases.every((c) => c.id && c.owner_id && Number.isInteger(c.version))
      )
        throw new ApiError("订单响应异常", 502);
      this.cases = r.cases;
      this.mode = "live";
      return this.cases;
    } catch (e) {
      if (generation !== this.generation) throw e;
      if (e.status && e.status < 500) throw e;
      this.mode = "demo";
      if (this.user.id !== "demo") this.cases = [];
      return this.cases.filter((c) => c.owner_id === "demo");
    }
  }
  async write(path, body) {
    if (this.pending) throw Error("上次提交结果待核对，请先核对");
    if (!this.user) throw new ApiError("请先登录", 401);
    const mutationKey = key(),
      generation = this.generation,
      wasDemo = this.mode === "demo";
    try {
      const r = await this.request(path, "POST", body, mutationKey);
      if (generation !== this.generation) throw Error("账户已变化");
      if (!r.case || !r.case.id || !Number.isInteger(r.case.version))
        throw new ApiError("提交响应异常", 502);
      this.mode = "live";
      this.upsert(r.case);
      return r.case;
    } catch (e) {
      if (generation !== this.generation) throw e;
      if (e.status && e.status < 500) throw e;
      if (wasDemo && this.user && this.user.id === "demo")
        return this.demoWrite(path, body);
      this.savePending({ key: mutationKey, path, body });
      throw Error("提交结果待核对，请勿再次提交同一事项");
    }
  }
  savePending(value) {
    this.pending = value;
    if (this.user && this.user.id !== "demo")
      this.wx.setStorageSync(
        "pending:" + this.base + ":" + this.user.id,
        value || "",
      );
  }
  upsert(c) {
    this.cases = [c, ...this.cases.filter((x) => x.id !== c.id)];
  }
  demoWrite(path, body) {
    if (path === "/cases") {
      const c = {
        ...body,
        id: key(),
        owner_id: "demo",
        status: "pending_review",
        version: 1,
        created_at: new Date().toISOString(),
        messages: [],
        attachments: [],
        events: [],
        order: null,
        quote: null,
      };
      this.upsert(c);
      return c;
    }
    const id = path.split("/")[2],
      c = JSON.parse(JSON.stringify(this.cases.find((x) => x.id === id)));
    if (!c) throw Error("演示记录不存在");
    if (body.action === "message" || body.action === "supplement") {
      c.messages.push({ id: key(), text: body.text, author_name: "本地演示" });
      c.version++;
      this.upsert(c);
      return c;
    }
    if (body.action === "withdraw_request") {
      c.status = "closed";
      c.version++;
      this.upsert(c);
      return c;
    }
    throw Error(
      "该复杂动作需要后端核验，演示模式仅支持新建、留言、补材料与撤回",
    );
  }
  async retryPending() {
    if (!this.pending || !this.pending.path || !this.pending.body)
      throw Error("此操作需要先核对原提交，附件不能自动重传");
    const saved = this.pending,
      generation = this.generation;
    try {
      const r = await this.request(saved.path, "POST", saved.body, saved.key);
      if (generation !== this.generation) throw new ApiError("账户已变化", 409);
      if (!r.case || !r.case.id || !Number.isInteger(r.case.version))
        throw new ApiError("提交响应异常", 502);
      this.savePending(null);
      this.upsert(r.case);
      return r.case;
    } catch (e) {
      if (generation === this.generation && e.status && e.status < 500)
        this.savePending(null);
      throw e;
    }
  }
  async reconcile() {
    if (!this.pending) return null;
    const r = await this.request(
      "/operations/" + encodeURIComponent(this.pending.key),
    );
    if (!r.case || !r.case.id || !Number.isInteger(r.case.version)) throw Error("核对响应异常");
    this.savePending(null);
    this.upsert(r.case);
    return r.case;
  }
  async upload(c) {
    if (this.mode === "demo") throw Error("附件需连接真实服务后上传");
    if (this.pending) throw Error("先核对待确认的提交");
    const requestGeneration = this.generation;
    const selection = await this.wx.chooseMessageFile({
      count: 1,
      type: "file",
    });
    if(requestGeneration !== this.generation) throw new ApiError("账户已变化",409);
    const file = selection.tempFiles[0];
    if (!file) return;
    const mutationKey = key();
    return new Promise((resolve, reject) =>
      this.wx.uploadFile({
        url: this.base + "/cases/" + c.id + "/attachments",
        filePath: file.path,
        name: "file",
        formData: { expected_version: String(c.version) },
        header: {
          Authorization: "Bearer " + this.token,
          "Idempotency-Key": mutationKey,
        },
        success: (r) => {
          if (requestGeneration !== this.generation) {
            reject(new ApiError("账户已变化", 409));
            return;
          }
          if (r.statusCode === 401) {
            this.logout();
            reject(Error("请重新登录"));
            return;
          }
          if (r.statusCode < 200 || r.statusCode >= 300) {
            if (r.statusCode >= 500) this.savePending({ key: mutationKey });
            reject(Error("上传未确认，请先核对"));
            return;
          }
          try {
            const data = JSON.parse(r.data);
            if (!data.case || !data.case.id) throw Error("响应异常");
            this.upsert(data.case);
            resolve(data.case);
          } catch (e) {
            this.savePending({ key: mutationKey });
            reject(e);
          }
        },
        fail: () => {
          if (requestGeneration === this.generation)
            this.savePending({ key: mutationKey });
          reject(Error("上传结果待核对"));
        },
      }),
    );
  }
  async download(c, id) {
    const requestGeneration = this.generation;
    return new Promise((resolve, reject) =>
      this.wx.downloadFile({
        url: this.base + "/cases/" + c.id + "/attachments/" + id,
        header: { Authorization: "Bearer " + this.token },
        timeout: 2500,
        success: (r) => {
          if (requestGeneration !== this.generation) {
            reject(Error("账户已变化"));
            return;
          }
          if (r.statusCode !== 200) {
            if (r.statusCode === 401) this.logout();
            reject(Error("无法取得文件，请检查权限和登录"));
            return;
          }
          this.wx.openDocument({
            filePath: r.tempFilePath,
            showMenu: true,
            success: resolve,
            fail: () => reject(Error("当前格式无法预览，请在桌面端下载")),
          });
        },
        fail: () => reject(Error("下载失败，请重新加载后重试")),
      }),
    );
  }
}
module.exports = { Client, ApiError, key };
