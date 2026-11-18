using System.Text.Json.Nodes;
using Zhixu;
using static Zhixu.ShopStore;

void Check(bool value,string label) { if(!value)throw new Exception(label); }
string preferences=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Jobs","ZhixuNative","preferences.json");
byte[]? originalPreferences=File.Exists(preferences)?File.ReadAllBytes(preferences):null;
try {
var store=new ShopStore { Api=args[0], Timeout=1500 };
await store.Refresh();Check(store.Online&&store.Products.Count>0,"live products");
await store.Login(new(){["account"]="customer",["password"]="demo-customer"});
var product=store.Products[0]!;
await store.Write("/shop-orders",new(){["product_id"]=S(product,"id"),["product_version"]=N(product,"version"),["requirements"]="C# native fixture",["contact"]="fixture",["delivery_requirements"]="fixture"});
var order=store.Orders[0]!;
Check(!S(order,"id").StartsWith("demo-"),"real order identity");
await store.Write("/shop-orders/"+S(order,"id")+"/actions",new(){["action"]="pay",["expected_version"]=N(order,"version"),["channel"]="wechat"});
order=store.Orders[0]!;Check(S(order,"status")=="pending_completion","mock payment");
string uid=S(store.User,"id");
string email="  任意邮箱 / unverified  ",phone="  +86 任意号码  ",mood="  慢慢来，每一步都算数。  ";
await store.SaveProfile(new(){["username"]="customer",["email"]=email,["phone"]=phone,["mood"]=mood});
Check(S(store.User,"id")==uid&&S(store.User,"email")==email&&S(store.User,"phone")==phone&&S(store.User,"mood")==mood,"live profile preserves UID and verbatim contacts");
await store.SaveProfile(new(){["mood"]="只更新心情"});
Check(S(store.User,"username")=="customer"&&S(store.User,"email")==email&&S(store.User,"phone")==phone&&S(store.User,"mood")=="只更新心情","partial mood retains profile fields");
try { await store.SaveProfile(new(){["id"]="client-uid"});throw new Exception("client changed UID"); }
catch(ApiException error)when(error.Status==422) { Check(S(store.User,"id")==uid,"rejected UID edit preserves local identity"); }
await store.SaveProfile(new(){["email"]="",["phone"]=""});
Check(S(store.User,"email")==""&&S(store.User,"phone")==""&&S(store.User,"id")==uid,"explicit contact clears");
try { await store.Login(new(){["account"]="customer",["password"]="wrong-password"});throw new Exception("401 demo bypass"); }
catch(ApiException error)when(error.Status==401) { Check(store.User==null,"401 session cleared"); }
store.Save(store.Language,store.Theme,"http://127.0.0.1:1/api/v1",1500);
await store.Login(new(){["account"]="customer",["password"]="demo-customer"});
string demoUID=S(store.User,"id");
await store.SaveProfile(new(){["email"]=email,["phone"]=phone,["mood"]=mood});
Check(!store.LiveSession&&S(store.User,"id")==demoUID&&S(store.User,"email")==email&&S(store.User,"phone")==phone&&S(store.User,"mood")==mood,"offline profile saves locally without altering UID");
await store.SaveProfile(new(){["mood"]="离线局部心情"});
Check(S(store.User,"email")==email&&S(store.User,"phone")==phone&&S(store.User,"mood")=="离线局部心情","offline partial mood retains contacts");
await store.Write("/shop-orders",new(){["product_id"]=S(store.Products[0],"id"),["product_version"]=N(store.Products[0],"version")});
Check(S(store.Orders[0],"id").StartsWith("demo-")&&!store.Online,"offline identity isolation");
store.Logout();
await store.Login(new(){["account"]="customer2",["password"]="demo-customer"});
Check(S(store.User,"id")!=demoUID&&S(store.User,"email")!=email&&S(store.User,"phone")!=phone&&S(store.User,"mood")!="离线局部心情"&&store.Orders.Count==0,"offline second user has no first-user profile or orders");
await store.SaveProfile(new(){["email"]="second-user-contact",["phone"]="second-user-phone",["mood"]="第二位用户"});
Check(S(store.User,"id")=="demo-customer2"&&S(store.User,"email")=="second-user-contact","second demo identity remains isolated");
Console.WriteLine("PASS C# native store: live buy/payment/SaveProfile, verbatim contacts and clears, read-only UID, partial mood, 401 rejection, isolated offline profiles/orders");
} finally {
    if(originalPreferences is null)File.Delete(preferences);
    else File.WriteAllBytes(preferences,originalPreferences);
}
