// Created by Jobs. Native Windows buyer store; session and demo data stay in memory.
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Zhixu;

sealed class ApiException(int status, string message, bool transport = false) : Exception(message)
{
    public int Status { get; } = status;
    public bool Offline => Status == 0 || Status >= 500;
    public bool TransportOffline { get; } = transport;
}

sealed class ShopStore
{
    public string Language = "zh", Theme = "system", Api = "http://127.0.0.1:8080/api/v1";
    public int Timeout = 2500;
    public JsonArray Products = [], Orders = [];
    public JsonArray? Banners;
    public JsonObject? User;
    public bool Online, LiveSession;
    public bool DemoAvailable { get; private set; }
    string demoEndpoint = "";
    bool knownProduction;
    readonly LocalDemoAuth demoAuth=new();
    public string Warning = "";
    private string token = "";
    private long epoch;
    private long revision;
    private long bannerRevision;
    private bool writing;
    private JsonArray demoOrders = [];
    private readonly JsonArray seed;
    private readonly JsonObject strings;
    private (string Path, JsonObject Body, string Key)? pending;
    private readonly HttpClient http;
    private readonly string preferencePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Jobs", "ZhixuNative", "preferences.json");
    public static readonly Dictionary<string, string> Languages = new() { ["zh"]="简体中文", ["zh-Hant"]="繁體中文", ["bo"]="བོད་ཡིག", ["en"]="English", ["ja"]="日本語", ["fr"]="Français", ["es"]="Español", ["de"]="Deutsch", ["ru"]="Русский", ["ko"]="한국어" };
    public static string S(JsonNode? node, string key) => node?[key]?.ToString() ?? "";
    public static int N(JsonNode? node, string key) => node?[key]?.GetValue<int>() ?? 0;
    public static bool B(JsonNode? node, string key) => node?[key]?.GetValue<bool>() ?? false;
    public static string Money(JsonNode? product, string key = "price_minor") => "¥" + (N(product,key)/100m).ToString("0.00");
    public string T(string key) => strings[Language]?[key]?.ToString() ?? strings["zh"]?[key]?.ToString() ?? key;
    public ShopStore(HttpMessageHandler? handler=null)
    {
        http=new HttpClient(handler??new HttpClientHandler{AllowAutoRedirect=false});
        var assets = Path.Combine(AppContext.BaseDirectory, "Assets");
        strings = JsonNode.Parse(File.ReadAllText(Path.Combine(assets,"shop_strings.json")))!.AsObject();
        seed = JsonNode.Parse(File.ReadAllText(Path.Combine(assets,"products.json")))!.AsArray();
        Products = [];
        try
        {
            var config = JsonNode.Parse(File.ReadAllText(preferencePath));
            Language = Languages.ContainsKey(S(config,"language")) ? S(config,"language") : "zh";
            Theme = S(config,"theme") is "light" or "dark" ? S(config,"theme") : "system";
            if (Uri.TryCreate(S(config,"api"),UriKind.Absolute,out var uri) && uri.Scheme is "http" or "https") Api = uri.ToString().TrimEnd('/');
            Timeout = Math.Clamp(N(config,"timeout"),500,10000);
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException) { }
    }
    public void Save(string language, string theme, string api, int timeout)
    {
        if (!Uri.TryCreate(api,UriKind.Absolute,out var uri) || uri.Scheme is not ("http" or "https") || uri.UserInfo.Length > 0 || uri.Query.Length > 0 || uri.Fragment.Length > 0) throw new ApiException(422,T("invalidLink"));
        if (Api != api) { Logout(); Online=false; Banners=null; Products=[]; DemoAvailable=false;knownProduction=false;demoEndpoint=""; }
        Language=language; Theme=theme; Api=api.TrimEnd('/'); Timeout=Math.Clamp(timeout,500,10000);
        Directory.CreateDirectory(Path.GetDirectoryName(preferencePath)!);
        File.WriteAllText(preferencePath, new JsonObject { ["language"]=Language,["theme"]=Theme,["api"]=Api,["timeout"]=Timeout }.ToJsonString());
    }
    public async Task<JsonObject> Request(string path, JsonObject? body=null, string? key=null, string? method=null)
    {
        long requestEpoch=epoch;
        using var request = new HttpRequestMessage(method is null ? (body is null ? HttpMethod.Get : HttpMethod.Post) : new HttpMethod(method),Api+path);
        if (token.Length>0) request.Headers.Authorization = new("Bearer",token);
        if (key!=null) request.Headers.Add("Idempotency-Key",key);
        if (body!=null) request.Content=new StringContent(body.ToJsonString(),Encoding.UTF8,"application/json");
        using var timeout = new CancellationTokenSource(Timeout);
        try
        {
            using var response = await http.SendAsync(request,timeout.Token);
            var text = await response.Content.ReadAsStringAsync(timeout.Token);
            if(requestEpoch!=epoch) throw new ApiException(499,T("reselect"));
            JsonObject? json;
            try { json=JsonNode.Parse(text)?.AsObject(); }
            catch (Exception error) when (error is JsonException or InvalidOperationException)
            {
                if(response.StatusCode==HttpStatusCode.Unauthorized)Logout();
                throw new ApiException(response.IsSuccessStatusCode ? 0 : (int)response.StatusCode,T("unexpected_response"));
            }
            if(!response.IsSuccessStatusCode)
            {
                if(response.StatusCode==HttpStatusCode.Unauthorized) Logout();
                throw new ApiException((int)response.StatusCode,json?["message"]?.ToString() ?? json?["error"]?.ToString() ?? response.StatusCode.ToString());
            }
            return json ?? throw new ApiException(0,T("unexpected_response"));
        }
        catch (Exception error) when(error is HttpRequestException or TaskCanceledException)
        {
            if(requestEpoch!=epoch) throw new ApiException(499,T("reselect"));
            throw new ApiException(0,T("updateFailed"),true);
        }
    }
    public async Task<JsonObject> Authentication(string path,JsonObject body)
    {
        try{return await Request(path,body);}
        catch(ApiException failure) when(failure.TransportOffline&&DemoAvailable){return demoAuth.Perform(path,body,T);}
    }

    public async Task CheckDemoMode()
    {
        if(demoEndpoint!=Api){demoEndpoint=Api;knownProduction=false;demoAuth.Reset();}
        long captured=epoch;
        DemoAvailable=false;
        if(!Uri.TryCreate(Api,UriKind.Absolute,out var uri) || !(uri.Host.Equals("localhost",StringComparison.OrdinalIgnoreCase) || IPAddress.TryParse(uri.Host.Trim('[',']'),out var ip)&&IPAddress.IsLoopback(ip)))
        {if(!Online && User==null)Products=[];return;}
        try
        {
            var config=await Request("/shop-config");
            if(captured!=epoch)return;
            if(config["demo_mode"] is JsonValue mode && mode.TryGetValue<bool>(out var enabled))
            {DemoAvailable=enabled;if(!enabled)knownProduction=true;}
        }
        catch(ApiException failure){if(captured==epoch)DemoAvailable=failure.TransportOffline&&!knownProduction;}
        if(captured==epoch&&!Online&&User==null)Products=DemoAvailable?seed.DeepClone().AsArray():[];
    }

    public async Task Refresh()
    {
        long requestEpoch=epoch;
        long readRevision=++revision;
        try
        {
            var response=await Request("/products");
            var products=response["products"]?.DeepClone().AsArray() ?? throw new ApiException(0,T("unexpected_response"));
            JsonArray? orders=null;
            if(LiveSession)
            {
                response=await Request("/shop-orders");
                orders=response["orders"]?.DeepClone().AsArray() ?? throw new ApiException(0,T("unexpected_response"));
            }
            if(requestEpoch!=epoch || readRevision!=revision)return;
            Products=products; Online=true; if(orders!=null)Orders=orders;
        }
        catch(ApiException)
        {
            if(requestEpoch!=epoch || readRevision!=revision)return;
            if(Online)Warning=T("updateFailed");
            else if(DemoAvailable)Orders=demoOrders.DeepClone().AsArray();
        }
    }
    public async Task Login(JsonObject values)
    {
        await CheckDemoMode();
        Logout();
        try
        {
            var response=await Request("/auth/login",values);
            if(S(response["user"],"role")!="customer" || S(response,"token").Length==0) throw new ApiException(403,T("customer"));
            token=S(response,"token"); User=response["user"]!.DeepClone().AsObject(); LiveSession=true;
        }
        catch(ApiException failure) when(failure.Offline)
        {
            if(!DemoAvailable)throw;
            User=demoAuth.Login(values,T); Online=false; Products=seed.DeepClone().AsArray(); Orders=demoOrders.DeepClone().AsArray();
        }
        await Refresh();
    }
    public async Task RefreshBanners()
    {
        long readRevision=++bannerRevision;
        try { var response=await Request("/banners");if(readRevision==bannerRevision)Banners=response["banners"]?.DeepClone().AsArray(); }
        catch(ApiException) { }
    }
    public async Task SaveProfile(JsonObject values)
    {
        if(User==null)throw new ApiException(401,T("signInFirst"));
        long captured=epoch;
        string identity=S(User,"id");
        try
        {
            var response=await Request("/auth/profile",values,method:"PUT");
            if(captured!=epoch)return;
            if(response["user"] is not JsonObject received || S(received,"id")!=identity)throw new ApiException(0,T("unexpected_response"));
            User=received.DeepClone().AsObject();
        }
        catch(ApiException failure)when(failure.TransportOffline&&!LiveSession&&DemoAvailable&&captured==epoch)
        {
            // Demo edits belong to this identity only and never upload on reconnect.
            foreach(string field in new[]{"username","email","phone","mood"})
            {
                if(values.ContainsKey(field))User![field]=S(values,field);
            }
            if(values.ContainsKey("username"))User!["name"]=S(values,"username");
            if(values.ContainsKey("avatar"))User!["avatar_url"]=S(values,"avatar");
        }
    }
    public void Logout() { epoch++; revision++; writing=false; token=""; User=null; LiveSession=false; Orders=[]; demoOrders=[]; pending=null; }
    public async Task Write(string path,JsonObject body)
    {
        if(User==null)throw new ApiException(401,T("signInFirst"));
        if(writing)throw new ApiException(409,T("pendingWrite"));
        if(pending is {} previous && (previous.Path!=path || !JsonNode.DeepEquals(previous.Body,body))) throw new ApiException(409,T("pendingWrite"));
        string key=pending?.Key ?? "windows-shop-"+Guid.NewGuid();
        long requestEpoch=epoch;
        writing=true;
        pending=(path,body.DeepClone().AsObject(),key);
        try
        {
            var result=await Request(path,body,key);
            var order=result["order"]?.AsObject() ?? throw new ApiException(0,T("unexpected_response"));
            bool valid=S(order,"id").Length>0 && N(order,"version")>0 && S(order,"owner_id")==S(User,"id") && order["product_snapshot"] is JsonObject;
            if(path=="/shop-orders")valid=valid && S(order["product_snapshot"],"id")==S(body,"product_id") && N(order["product_snapshot"],"version")==N(body,"product_version");
            else valid=valid && path=="/shop-orders/"+S(order,"id")+"/actions" && N(order,"version")>N(body,"expected_version");
            if(!valid)throw new ApiException(0,T("unexpected_response"));
            Orders=new JsonArray(Orders.Where(x=>S(x,"id")!=S(order,"id")).Select(x=>x!.DeepClone()).ToArray());
            Orders.Insert(0,order.DeepClone()); Online=true; pending=null; revision++;
        }
        catch(ApiException failure) when(failure.Offline)
        {
            if(LiveSession) { pending=(path,body.DeepClone().AsObject(),key); throw new ApiException(0,T("pendingWrite")); }
            if(!DemoAvailable)throw;
            ApplyDemo(path,body);pending=null;revision++;
        }
        catch(ApiException failure) when(!failure.Offline)
        { if(requestEpoch==epoch)pending=null;throw; }
        finally { if(requestEpoch==epoch)writing=false; }
    }
    public async Task Retry() { if(pending is {} value) await Write(value.Path,value.Body); }
    private void ApplyDemo(string path,JsonObject body)
    {
        if(path=="/shop-orders")
        {
            var p=Products.FirstOrDefault(x=>S(x,"id")==S(body,"product_id"));
            if(p==null || !B(p,"in_stock") || N(p,"version")!=N(body,"product_version"))throw new ApiException(422,T("outOfStock"));
            var order=new JsonObject { ["id"]="demo-"+Guid.NewGuid(),["product_snapshot"]=p.DeepClone(),["amount_minor"]=N(p,"price_minor"),["status"]="pending_payment",["fulfillment_status"]="pending",["editable"]=true,["version"]=1,["requirements"]=S(body,"requirements"),["contact"]=S(body,"contact"),["delivery_requirements"]=S(body,"delivery_requirements") };
            demoOrders.Insert(0,order);
        }
        else
        {
            var order=demoOrders.FirstOrDefault(x=>path.Contains(S(x,"id")))?.AsObject();
            if(order==null || N(order,"version")!=N(body,"expected_version"))throw new ApiException(409,T("version"));
            switch(S(body,"action"))
            {
                case "pay" when S(order,"status")=="pending_payment": order["status"]="pending_completion";break;
                case "cancel" when S(order,"status")=="pending_payment": order["status"]="cancelled";order["editable"]=false;break;
                case "edit" when B(order,"editable"):
                    foreach(var field in new[]{"requirements","contact","delivery_requirements"})order[field]=S(body,field);
                    break;
                case "accept" when S(order,"fulfillment_status")=="delivered": order["status"]="pending_review";break;
                case "review" when S(order,"status")=="pending_review": order["status"]="completed";break;
                default:throw new ApiException(422,T("state"));
            }
            order["version"]=N(order,"version")+1;
        }
        Orders=demoOrders.DeepClone().AsArray();Online=false;
    }
}
