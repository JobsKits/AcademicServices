// Created by Jobs. Local-only disposable demo authentication, with code expiry and salted password hashes.
using System.Net.Mail;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using static Zhixu.ShopStore;

namespace Zhixu;

sealed class LocalDemoAuth
{
    sealed record Account(string Username,string Email,byte[] Salt,byte[] Digest,string Id);
    sealed record Code(string Value,DateTimeOffset Expires,DateTimeOffset Sent,int Attempts);
    readonly Dictionary<string,Account> accounts=new(StringComparer.OrdinalIgnoreCase);
    readonly Dictionary<string,Code> codes=new(StringComparer.OrdinalIgnoreCase);
    public void Reset(){accounts.Clear();codes.Clear();}
    public JsonObject Login(JsonObject values,Func<string,string> t)
    {
        string name=S(values,"account"),password=S(values,"password");
        if(name is "customer" or "customer2" && password=="demo-customer")return new(){["id"]="demo-"+name,["username"]=name,["name"]=name,["role"]="customer"};
        var account=accounts.Values.FirstOrDefault(a=>a.Username.Equals(name,StringComparison.OrdinalIgnoreCase)||a.Email.Equals(name,StringComparison.OrdinalIgnoreCase));
        if(account==null||!CryptographicOperations.FixedTimeEquals(account.Digest,Hash(password,account.Salt)))throw new ApiException(401,t("loginHint"));
        return new(){["id"]=account.Id,["username"]=account.Username,["name"]=account.Username,["email"]=account.Email,["role"]="customer"};
    }
    public JsonObject Perform(string path,JsonObject values,Func<string,string> t)
    {
        string email=S(values,"email").Trim().ToLowerInvariant();
        if(!MailAddress.TryCreate(email,out var parsed)||parsed.Address!=email)throw new ApiException(422,t("required"));
        if(path=="/auth/email-code")
        {
            string purpose=S(values,"purpose");if(purpose is not ("register" or "reset_password"))throw new ApiException(422,t("required"));
            string key=email+":"+purpose;
            if(codes.TryGetValue(key,out var previous)&&DateTimeOffset.UtcNow<previous.Sent.AddSeconds(60))throw new ApiException(429,t("codeSent"));
            string code=RandomNumberGenerator.GetInt32(1000000).ToString("D6");var now=DateTimeOffset.UtcNow;codes[key]=new(code,now.AddMinutes(10),now,0);
            return new(){["demo_code"]=code,["expires_in"]=600};
        }
        bool register=path=="/auth/register";
        if(!register&&path!="/auth/reset-password")throw new ApiException(404,t("required"));
        string password=S(values,"password");
        if(password.Length<8||Encoding.UTF8.GetByteCount(password)>256||password!=S(values,"confirm_password"))throw new ApiException(422,t("required"));
        string user=S(values,"username");
        if(register&&(!Regex.IsMatch(user,@"^[\p{L}\p{N}_-]{3,32}$")||user is "customer" or "customer2"||accounts.Values.Any(a=>a.Username.Equals(user,StringComparison.OrdinalIgnoreCase)||a.Email==email)))throw new ApiException(409,t("required"));
        string lookup=email+":"+(register?"register":"reset_password");
        if(!codes.TryGetValue(lookup,out var current)||current.Expires<DateTimeOffset.UtcNow||current.Attempts>=5)throw new ApiException(422,t("required"));
        codes[lookup]=current with{Attempts=current.Attempts+1};
        if(!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(current.Value),Encoding.UTF8.GetBytes(S(values,"code"))))throw new ApiException(422,t("required"));
        if(register)
        {
            var salt=RandomNumberGenerator.GetBytes(16);accounts[user]=new(user,email,salt,Hash(password,salt),"demo-"+Guid.NewGuid());
        }
        else
        {
            var existing=accounts.Values.FirstOrDefault(a=>a.Email==email);if(existing==null)throw new ApiException(404,t("required"));
            var salt=RandomNumberGenerator.GetBytes(16);accounts[existing.Username]=existing with{Salt=salt,Digest=Hash(password,salt)};
        }
        codes.Remove(lookup);return new(){["ok"]=true};
    }
    static byte[] Hash(string value,byte[] salt)=>Rfc2898DeriveBytes.Pbkdf2(value,salt,150000,HashAlgorithmName.SHA256,32);
}
