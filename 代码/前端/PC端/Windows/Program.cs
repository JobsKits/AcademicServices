// Created by Jobs. Windows Forms native UI, no browser or Python runtime.
using Microsoft.Win32;
using System.Text.Json.Nodes;
using static Zhixu.ShopStore;

namespace Zhixu;

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new ShopWindow());
    }
}

sealed class ShopWindow : Form
{
    readonly ShopStore store = new();
    readonly FlowLayoutPanel navigation = new() { Dock=DockStyle.Top,AutoSize=true,Padding=new(14),WrapContents=false };
    readonly FlowLayoutPanel content = new() { Dock=DockStyle.Fill,AutoScroll=true,Padding=new(24),WrapContents=true };
    readonly FlowLayoutPanel footer = new() { Dock=DockStyle.Bottom,AutoSize=true,Padding=new(12) };
    string page="home",category="all",filter="all";
    JsonNode? detail;
    bool busy;
    bool authOpen;
    int bannerIndex;
    bool foreground=true;
    FlowLayoutPanel? bannerArea;
    InlineSlogan? slogan;
    NativeCategoryPager? categoryPager;
    NativeOrderPager? orderPager;
    readonly System.Windows.Forms.Timer bannerTimer=new(){Interval=4500};
    public ShopWindow()
    {
        Text="知序"; Width=1140;Height=820;MinimumSize=new(960,600);
        Font=new("Segoe UI",10);
        Controls.Add(content);Controls.Add(footer);Controls.Add(navigation);
        Shown+=async (_,_)=>await Run(RefreshAll);
        Activated+=(_,_)=>foreground=true;
        Deactivate+=(_,_)=>foreground=false;
        bannerTimer.Tick+=(_,_)=>{if(foreground&&!NativeMotion.Reduced&&page=="home"&&detail==null&&store.Banners is {Count:>1} banners){bannerIndex=(bannerIndex+1)%banners.Count;RenderBanner();}};
        bannerTimer.Start();
        Resize+=(_,_)=>Reflow();
        SystemEvents.UserPreferenceChanged+=OnSystemTheme;
        FormClosed+=(_,_)=>{SystemEvents.UserPreferenceChanged-=OnSystemTheme;bannerTimer.Dispose();};
        Render();
    }
    void OnSystemTheme(object sender,UserPreferenceChangedEventArgs e)
    {
        if(store.Theme=="system" && !IsDisposed) BeginInvoke(()=>ApplyTheme(this));
    }
    Button Button(string key, Action click, bool selected=false)
    {
        var button=new Button { Text=store.T(key),AutoSize=true,MinimumSize=new(90,40),Margin=new(4),Padding=new(8,3,8,3),UseVisualStyleBackColor=false };
        button.Tag=selected?"selected":null;button.Click+=(_,_)=>click();return button;
    }
    static Label Label(string text,float size=11,bool bold=false,int width=280)
    {
        return new Label { Text=text,AutoSize=true,Width=width,MinimumSize=new(width,35),MaximumSize=new(width,0),Font=new("Segoe UI",size,bold?FontStyle.Bold:FontStyle.Regular),Margin=new(4),AutoEllipsis=false };
    }
    static void Clear(Control control)
    {
        foreach(Control child in control.Controls.Cast<Control>().ToArray())child.Dispose();
    }
    async Task Run(Func<Task> operation)
    {
        if(busy)return;
        busy=true;navigation.Enabled=false;footer.Enabled=false;
        try { await operation(); }
        catch(Exception error) { MessageBox.Show(this,error.Message,Text,MessageBoxButtons.OK,MessageBoxIcon.Information); }
        finally { busy=false;navigation.Enabled=true;footer.Enabled=true;Render(); }
    }
    async Task RefreshAll() { await store.CheckDemoMode();await store.Refresh();await store.RefreshBanners(); }
    void Render()
    {
        if(IsDisposed)return;
        SuspendLayout();Clear(navigation);Clear(content);Clear(footer);categoryPager=null;orderPager=null;
        navigation.Controls.Add(Label("知序",21,true,95));
        foreach(string item in new[]{"home","myOrders","mine"})
        {
            var destination=Button(item,()=>Navigate(item),page==item);destination.MaximumSize=new(160,48);destination.AutoEllipsis=true;navigation.Controls.Add(destination);
        }
        slogan=new InlineSlogan(store.T("hero"),store.T("intro")){Height=48,Margin=new(22,0,12,0)};
        navigation.Controls.Add(slogan);
        if(store.User==null)navigation.Controls.Add(Button("login",()=>Auth()));
        else
        {
            var account=Button(S(store.User,"name"),()=>{});account.Text=S(store.User,"name");account.MaximumSize=new(160,48);account.AutoEllipsis=true;account.AccessibleDescription=store.T("accountMenu");
            account.Click+=(_,_)=>ShowAccountMenu(account);navigation.Controls.Add(account);
        }
        footer.Controls.Add(Label(store.T(store.Online?"online":store.DemoAvailable?"offline":"serverUnavailable"),10,false,250));
        var settingsButton=Button("settings",Settings);settingsButton.Text="";settingsButton.Width=42;settingsButton.MinimumSize=new(42,38);settingsButton.AutoSize=false;settingsButton.AccessibleName=store.T("settings");
        settingsButton.Paint+=(_,e)=>DrawGear(e.Graphics,settingsButton.ClientRectangle,settingsButton.ForeColor);
        footer.Controls.Add(settingsButton);
        if(detail!=null)Detail(detail);
        else if(page=="home")Home();
        else if(store.User==null)SignInRequired();
        else if(page=="myOrders")Orders();
        else Profile();
        if(store.Warning.Length>0){footer.Controls.Add(Label(store.Warning,10,false,400));store.Warning="";}
        Reflow();ApplyTheme(this);ResumeLayout();
    }
    FlowLayoutPanel Section(int width=950)
    {
        return new FlowLayoutPanel { FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,MinimumSize=new(width,0),MaximumSize=new(width,0),Width=width,Margin=new(8),Padding=new(16),BorderStyle=BorderStyle.FixedSingle };
    }
    void Home()
    {
        var hero=Section();hero.BorderStyle=BorderStyle.None;hero.Padding=new(0);hero.Margin=new(8,0,8,18);
        bannerArea=new FlowLayoutPanel { Width=890,AutoSize=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,Margin=new(0) };
        hero.Controls.Add(bannerArea);RenderBanner();content.Controls.Add(hero);
        categoryPager=new NativeCategoryPager(store,category,ProductPage,value=>category=value){Width=950,Margin=new(8,0,8,8),Tag="full"};
        content.Controls.Add(categoryPager);
    }
    FlowLayoutPanel ProductPage(string selectedCategory)
    {
        var panel=new FlowLayoutPanel{Width=950,WrapContents=true};
        var products=store.Products.Where(p=>B(p,"active")&&(selectedCategory=="all"||S(p,"category_id")==selectedCategory)).ToArray();
        if(products.Length==0)
        {
            var empty=EmptyBody("emptyProducts",850);empty.Tag="emptyCategory";panel.Controls.Add(empty);
        }
        foreach(var product in products)
        {
            var card=new NativeProductCard(()=>{detail=product;Render();}){AccessibleName=S(product,"name")+" "+Money(product)};
            card.Controls.Add(Picture(product,266,115));
            card.Controls.Add(Label(store.T(S(product,"category_id")),10,false,266));
            card.Controls.Add(Label(S(product,"name"),16,true,266));
            card.Controls.Add(Label(S(product,"summary"),10,false,266));
            card.Controls.Add(Label(Money(product),19,true,266));
            card.Controls.Add(Button("details",()=>{detail=product;Render();}));card.BindChildren();panel.Controls.Add(card);
        }
        return panel;
    }
    void RenderBanner()
    {
        if(bannerArea==null||bannerArea.IsDisposed)return;Clear(bannerArea);
        if(store.Banners?.Count==0)return;
        var current=store.Banners?[bannerIndex%store.Banners.Count];
        var asset=new JsonObject { ["category_id"]="graduation",["image"]=S(current,"image") };
        int width=Math.Max(600,bannerArea.Width-8);
        var picture=Picture(asset,width,BannerHeight(width));picture.Margin=new(0);
        Point? start=null;
        picture.MouseDown+=(_,e)=>{if(e.Button==MouseButtons.Left)start=e.Location;};
        picture.MouseUp+=(_,e)=>
        {
            if(start is not {} origin)return;start=null;
            if(Math.Abs(e.X-origin.X)>60&&store.Banners?.Count>1)
            {
                bannerIndex=(bannerIndex+(e.X<origin.X?1:store.Banners.Count-1))%store.Banners.Count;bannerTimer.Stop();bannerTimer.Start();RenderBanner();
            }
        };
        picture.Click+=(_,_)=>{if(Uri.TryCreate(S(current,"target_url"),UriKind.Absolute,out var uri)&&uri.Scheme is "http" or "https")System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri.ToString()){UseShellExecute=true});};
        bannerArea.Controls.Add(picture);
        if(store.Banners?.Count>1)
        {
            var dots=new FlowLayoutPanel { AutoSize=false,Width=width,Height=42,FlowDirection=FlowDirection.LeftToRight,Padding=new(Math.Max(0,(width-store.Banners.Count*34)/2),0,0,0),Margin=new(0,4,0,0) };
            for(int i=0;i<store.Banners.Count;i++)
            {
                int target=i;var dot=new Button {Text=i==bannerIndex%store.Banners.Count?"●":"○",Width=28,Height=32,FlatStyle=FlatStyle.Flat,AccessibleName=store.T("banners")+" "+(i+1)};dot.FlatAppearance.BorderSize=0;
                dot.Click+=(_,_)=>{bannerIndex=target;bannerTimer.Stop();bannerTimer.Start();RenderBanner();};dots.Controls.Add(dot);
            }
            bannerArea.Controls.Add(dots);
        }
        ApplyTheme(bannerArea);
    }
    PictureBox Picture(JsonNode? product,int width,int height)
    {
        var picture=new PictureBox { Width=width,Height=height,SizeMode=PictureBoxSizeMode.Zoom,Margin=new(4) };
        var path=Path.Combine(AppContext.BaseDirectory,"Assets",product==null?"icon.png":S(product,"category_id")+".png");
        try { picture.Image=Image.FromFile(path); }
        catch(IOException) { }
        string source=S(product,"image");
        if(source.StartsWith("data:image/",StringComparison.Ordinal))
        {
            try{using var stream=new MemoryStream(Convert.FromBase64String(source[(source.IndexOf(',')+1)..]));using var decoded=Image.FromStream(stream);picture.Image?.Dispose();picture.Image=new Bitmap(decoded);}
            catch(Exception error)when(error is FormatException or ArgumentException){ }
        }
        else if(product!=null && !string.IsNullOrWhiteSpace(source) && Uri.TryCreate(new Uri(store.Api),source,out var uri) && uri.Scheme is "http" or "https")
        {
            var fallback=picture.Image;
            picture.LoadCompleted+=(_,eventArgs)=>{if(eventArgs.Error!=null&&!picture.IsDisposed)picture.Image=fallback;};
            try { picture.LoadAsync(uri.ToString()); }catch(InvalidOperationException) { }
        }
        picture.Disposed+=(_,_)=>picture.Image?.Dispose();return picture;
    }
    void Detail(JsonNode product)
    {
        var panel=Section();panel.Tag="full";
        var back=Button("back",()=>{detail=null;Render();});back.Padding=new(28,3,12,3);back.TextAlign=ContentAlignment.MiddleRight;
        back.Paint+=(_,e)=>DrawBackArrow(e.Graphics,new Point(12,back.Height/2),back.ForeColor);panel.Controls.Add(back);
        panel.Controls.Add(Label(S(product,"name"),25,true,850));panel.Controls.Add(Picture(product,850,210));
        panel.Controls.Add(Label(Money(product),22,true,850));
        panel.Controls.Add(new TextBox { Text=S(product,"description"),ReadOnly=true,Multiline=true,ScrollBars=ScrollBars.Vertical,Width=850,Height=110 });
        foreach(var section in product["sections"]?.AsArray()??[])
        {
            panel.Controls.Add(Label(S(section,"title"),16,true,850));
            panel.Controls.Add(new TextBox { Text=S(section,"body"),ReadOnly=true,Multiline=true,Width=850,Height=85 });
        }
        var buy=Button(B(product,"in_stock")?"buy":"outOfStock",()=>{if(store.User==null)Auth();else Requirements(product,null);});buy.Enabled=B(product,"in_stock");panel.Controls.Add(buy);content.Controls.Add(panel);
    }
    void Empty(string key)
    {
        var empty=EmptyBody(key,850);empty.Tag="full";content.Controls.Add(empty);
    }
    FlowLayoutPanel EmptyBody(string key,int width)
    {
        var empty=new FlowLayoutPanel{Width=width,Height=260,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new(0,20,0,0),Margin=new(0)};
        var image=Picture(null,74,74);image.Tag="fixedImage";image.Margin=new(Math.Max(0,(width-74)/2),0,0,14);empty.Controls.Add(image);
        var title=Label(store.T(key),18,true,width);title.TextAlign=ContentAlignment.MiddleCenter;empty.Controls.Add(title);
        var hint=Label(store.T("emptyHint"),10,false,width);hint.TextAlign=ContentAlignment.MiddleCenter;empty.Controls.Add(hint);
        var reload=Button("reload",()=>_ = Run(store.Refresh));reload.Margin=new(Math.Max(0,(width-140)/2),10,0,0);reload.MinimumSize=new(140,40);empty.Controls.Add(reload);
        empty.SizeChanged+=(_,_)=>
        {
            image.Margin=new(Math.Max(0,(empty.Width-image.Width)/2),0,0,14);
            foreach(Control label in new Control[]{title,hint}){label.MinimumSize=new(Math.Max(100,empty.Width-8),35);label.MaximumSize=new(Math.Max(100,empty.Width-8),0);}
            reload.Margin=new(Math.Max(0,(empty.Width-reload.Width)/2),10,0,0);
        };
        return empty;
    }
    void Orders()
    {
        orderPager=new NativeOrderPager(store,filter,OrderPage,value=>filter=value){Width=950,Margin=new(8,0,8,0)};
        content.Controls.Add(orderPager);
    }
    FlowLayoutPanel OrderPage(string selectedStatus)
    {
        var result=new FlowLayoutPanel{Width=950,FlowDirection=FlowDirection.TopDown,WrapContents=false};
        var orders=store.Orders.Where(o=>selectedStatus=="all"||S(o,"status")==selectedStatus).ToArray();
        if(orders.Length==0)
        {
            var empty=EmptyBody("emptyOrders",950);empty.Tag="orderDataEmpty";result.Controls.Add(empty);
        }
        foreach(var candidate in orders)
        {
            if(candidate is not JsonObject order)continue;
            var panel=Section();panel.Tag="full";
            panel.Controls.Add(Label(S(order["product_snapshot"],"name"),20,true,850));
            panel.Controls.Add(Label(S(order,"id"),9,false,850));
            panel.Controls.Add(Label(Money(order,"amount_minor")+"  "+store.T(S(order,"status"))+"  "+store.T(S(order,"fulfillment_status")),13,true,850));
            panel.Controls.Add(new TextBox { Text=S(order,"requirements")+Environment.NewLine+S(order,"delivery_text"),Width=850,Height=75,ReadOnly=true,Multiline=true });
            var actions=new FlowLayoutPanel { AutoSize=true,Width=850 };
            if(B(order,"editable"))actions.Controls.Add(Button("editRequirements",()=>Requirements(null,order)));
            if(S(order,"status")=="pending_payment")
            {
                foreach(string channel in new[]{"alipay","wechat"})actions.Controls.Add(Button(channel,()=>Action(order,"pay",new JsonObject { ["channel"]=channel })));
                actions.Controls.Add(Button("cancel",()=>Action(order,"cancel",new())));
            }
            if(S(order,"status")=="pending_completion" && S(order,"fulfillment_status")=="delivered")actions.Controls.Add(Button("accept",()=>Action(order,"accept",new())));
            if(S(order,"status")=="pending_review")actions.Controls.Add(Button("review",()=>Action(order,"review",new())));
            panel.Controls.Add(actions);result.Controls.Add(panel);
        }
        return result;
    }
    void Requirements(JsonNode? product,JsonNode? order)
    {
        using var dialog=new NativeDialog(store,order==null?"buy":"editRequirements",[("requirements","multiline"),("contact","text"),("deliveryRequirements","multiline")],new() { ["requirements"]=S(order,"requirements"),["contact"]=S(order,"contact"),["deliveryRequirements"]=S(order,"delivery_requirements") });
        dialog.Submit=async values=>
        {
            values["delivery_requirements"]=values["deliveryRequirements"]?.DeepClone();values.Remove("deliveryRequirements");
            if(product!=null){values["product_id"]=S(product,"id");values["product_version"]=N(product,"version");await store.Write("/shop-orders",values);}
            else {values["action"]="edit";values["expected_version"]=N(order,"version");await store.Write("/shop-orders/"+S(order,"id")+"/actions",values);}
        };
        dialog.ShowDialog(this);Render();
    }
    void Action(JsonNode order,string action,JsonObject extra)
    {
        using var dialog=new NativeDialog(store,action=="pay"?"mockHint":action,action=="review"?[("rating","number"),("text","multiline")]:[],new() { ["rating"]="5" });
        dialog.Submit=async values=>
        {
            foreach(var field in extra)values[field.Key]=field.Value?.DeepClone();
            values["action"]=action;values["expected_version"]=N(order,"version");
            if(action=="review")
            {
                if(!int.TryParse(S(values,"rating"),out var rating)||rating<1||rating>5||string.IsNullOrWhiteSpace(S(values,"text")))throw new ApiException(422,store.T("requiredReview"));
                values["rating"]=rating;
            }
            await store.Write("/shop-orders/"+S(order,"id")+"/actions",values);
        };
        dialog.ShowDialog(this);Render();
    }
    void Navigate(string destination)
    {
        if(destination!="home"&&store.User==null){Auth("login",destination);return;}
        page=destination;detail=null;Render();_ = Run(RefreshAll);
    }
    void SignInRequired()
    {
        var panel=Section();panel.Tag="full";panel.Controls.Add(Picture(null,64,64));
        panel.Controls.Add(Label(store.T("signInFirst"),22,true,800));
        panel.Controls.Add(Label(store.T("authRequiredHint"),11,false,800));
        panel.Controls.Add(Button("login",()=>Auth("login",page)));content.Controls.Add(panel);
    }
    async void Auth(string mode="login",string? destination=null)
    {
        if(authOpen)return;authOpen=true;
        try
        {
            await store.CheckDemoMode();
            using var dialog=new NativeAuthDialog(store,mode);
            dialog.ShowDialog(this);
            if(dialog.SignedIn&&store.User!=null){page=destination??page;detail=null;}
        }
        catch(Exception error){MessageBox.Show(this,error.Message,Text,MessageBoxButtons.OK,MessageBoxIcon.Information);}
        finally{authOpen=false;Render();}
    }
    void Profile()
    {
        var panel=Section();panel.Tag="full";panel.BorderStyle=BorderStyle.None;panel.Padding=new(12,18,12,24);
        if(store.DemoAvailable)panel.Controls.Add(Label(store.T("demoVersion"),10,true,850));
        var avatar=new NativeAvatarPicture{Width=102,Height=102,Tag="fixedImage",Cursor=Cursors.Hand,AccessibleName=store.T("chooseAvatar"),Margin=new(4,6,4,14)};
        try{avatar.Image=Image.FromFile(Path.Combine(AppContext.BaseDirectory,"Assets","icon.png"));}catch(IOException){ }
        string encoded=S(store.User,"avatar_url");
        if(encoded.StartsWith("data:image/",StringComparison.Ordinal))
        {
            try{avatar.SetEncoded(encoded);}
            catch(Exception error)when(error is FormatException or ArgumentException){ }
        }
        else if(Uri.TryCreate(encoded,UriKind.Absolute,out var avatarUri)&&avatarUri.Scheme is "http" or "https")
        {
            var fallback=avatar.Image;avatar.LoadCompleted+=(_,e)=>{if(e.Error!=null&&!avatar.IsDisposed)avatar.Image=fallback;};avatar.LoadAsync(avatarUri.ToString());
        }
        avatar.Click+=(_,_)=>{using var dialog=new NativeAvatarDialog(store);dialog.ShowDialog(this);Render();};
        panel.Controls.Add(avatar);
        var choose=Button("chooseAvatar",()=>{using var dialog=new NativeAvatarDialog(store);dialog.ShowDialog(this);Render();});panel.Controls.Add(choose);
        var mood=new FlowLayoutPanel{Width=850,AutoSize=true,Margin=new(0,4,0,22)};
        var editMood=Button("editMood",()=>
        {
            using var dialog=new NativeDialog(store,"editMood",[("mood","multiline")],new(){["mood"]=S(store.User,"mood")});
            dialog.Submit=store.SaveProfile;dialog.ShowDialog(this);Render();
        });
        editMood.Text="✍️";editMood.AccessibleName=store.T("editMood");editMood.MinimumSize=new(42,38);editMood.AutoSize=false;editMood.Width=42;
        mood.Controls.Add(editMood);
        mood.Controls.Add(Label(S(store.User,"mood").Length==0?store.T("defaultMood"):S(store.User,"mood"),11,false,690));panel.Controls.Add(mood);
        panel.Controls.Add(Label(S(store.User,"name"),25,true,850));
        panel.Controls.Add(Label(store.T("uid")+"  "+S(store.User,"id"),10,false,850));
        panel.Controls.Add(Label(store.T("email")+"  "+S(store.User,"email"),11,false,850));
        panel.Controls.Add(Label(store.T("phone")+"  "+S(store.User,"phone"),11,false,850));
        panel.Controls.Add(Button("saveProfile",()=>
        {
            using var dialog=new NativeDialog(store,"saveProfile",[("uid","readonly"),("username","text"),("email","text"),("phone","text")],new(){["uid"]=S(store.User,"id"),["username"]=S(store.User,"username"),["email"]=S(store.User,"email"),["phone"]=S(store.User,"phone")});
            dialog.Submit=async values=>{values.Remove("uid");await store.SaveProfile(values);};
            dialog.ShowDialog(this);Render();
        }));
        panel.Controls.Add(Button("myOrders",()=>Navigate("myOrders")));panel.Controls.Add(Label(store.T("orderEntryHint"),10,false,850));
        content.Controls.Add(panel);
    }
    void ShowAccountMenu(Control anchor)
    {
        bool dark=IsDarkTheme;
        var menu=new ContextMenuStrip{ShowImageMargin=false,ShowCheckMargin=false,Padding=new(6),AccessibleName=store.T("accountMenu"),Renderer=new AccountMenuRenderer(dark)};
        var change=new ToolStripMenuItem(store.T("switchAccount")){Padding=new(14,10,14,10)};
        var exit=new ToolStripMenuItem(store.T("exit")){Padding=new(14,10,14,10),Tag="exit"};
        change.Click+=(_,_)=>BeginInvoke(()=>
        {
            store.Logout();page="home";detail=null;Render();Auth("login");
        });
        exit.Click+=(_,_)=>BeginInvoke(()=>{store.Logout();page="home";detail=null;Render();});
        menu.Items.Add(change);menu.Items.Add(exit);
        menu.Closed+=(_,_)=>BeginInvoke(menu.Dispose);
        menu.Show(anchor,new Point(Math.Max(0,anchor.Width-menu.PreferredSize.Width),anchor.Height));
    }
    void Settings()
    {
        (string,string)[] fields=store.DemoAvailable?[("appearance","heading"),("language","language"),("theme","theme"),("connection","heading"),("api","text"),("timeout","number")]:[("appearance","heading"),("language","language"),("theme","theme")];
        using var dialog=new NativeDialog(store,"settings",fields,new(){["language"]=store.Language,["theme"]=store.Theme,["api"]=store.Api,["timeout"]=store.Timeout.ToString()});
        dialog.Submit=async values=>
        {
            string address=store.Api;int timeout=store.Timeout;
            if(store.DemoAvailable)
            {
                if(!int.TryParse(S(values,"timeout"),out timeout)||timeout<500||timeout>10000)throw new ApiException(422,store.T("timeout"));
                address=S(values,"api");
            }
            store.Save(S(values,"language"),S(values,"theme"),address,timeout);await RefreshAll();
        };
        dialog.ShowDialog(this);Render();
    }
    void Reflow()
    {
        if(slogan!=null)
        {
            int occupied=navigation.Controls.Cast<Control>().Where(c=>c!=slogan).Sum(c=>c.Width+c.Margin.Horizontal);
            int sloganWidth=Math.Max(80,navigation.ClientSize.Width-occupied-navigation.Padding.Horizontal-46);
            slogan.Width=sloganWidth;
        }
        int available=Math.Max(600,content.ClientSize.Width-70);
        foreach(Control panel in content.Controls)
        {
            if(panel is NativeCategoryPager pager){pager.Width=available;continue;}
            if(panel is NativeOrderPager ordersPager)
            {
                ordersPager.SetAvailableSize(available,content.ClientSize.Height-content.Padding.Vertical-panel.Margin.Vertical-8);continue;
            }
            if(panel is FlowLayoutPanel && panel.Tag?.ToString()!="card")
            {
                int width=Math.Max(600,content.ClientSize.Width-70);
                panel.MinimumSize=new(width,0);panel.MaximumSize=new(width,0);panel.Width=width;
                foreach(Control child in panel.Controls)
                {
                    if(child.Tag?.ToString()=="fixedImage")continue;
                    int inner=Math.Max(540,width-45);
                    if(child is System.Windows.Forms.Label)
                    {child.MinimumSize=new(inner,35);child.MaximumSize=new(inner,0);child.Width=inner;}
                    else if(child is TextBox or PictureBox or FlowLayoutPanel)child.Width=inner;
                }
            }
        }
        if(bannerArea!=null&&!bannerArea.IsDisposed)
        {
            int width=Math.Max(600,bannerArea.Width-8);
            foreach(Control child in bannerArea.Controls)
            {
                child.Width=width;
                if(child is PictureBox)child.Height=BannerHeight(width);
                else if(child is FlowLayoutPanel dots)dots.Padding=new(Math.Max(0,(width-dots.Controls.Count*34)/2),0,0,0);
            }
        }
    }
    static int BannerHeight(int width)=>Math.Clamp((int)Math.Round(width*0.405),240,390)/2;
    static void DrawGear(Graphics graphics,Rectangle area,Color color)
    {
        graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        float cx=area.Width/2f,cy=area.Height/2f;
        using var pen=new Pen(color,1.6f);
        graphics.DrawEllipse(pen,cx-7,cy-7,14,14);graphics.DrawEllipse(pen,cx-2.5f,cy-2.5f,5,5);
        for(int i=0;i<8;i++)
        {
            double angle=i*Math.PI/4;
            graphics.DrawLine(pen,cx+(float)Math.Cos(angle)*7,cy+(float)Math.Sin(angle)*7,cx+(float)Math.Cos(angle)*10,cy+(float)Math.Sin(angle)*10);
        }
    }
    static void DrawBackArrow(Graphics graphics,Point center,Color color)
    {
        graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        using var pen=new Pen(color,1.8f){StartCap=System.Drawing.Drawing2D.LineCap.Round,EndCap=System.Drawing.Drawing2D.LineCap.Round};
        graphics.DrawLine(pen,center.X,center.Y,center.X+12,center.Y);
        graphics.DrawLine(pen,center.X,center.Y,center.X+5,center.Y-5);
        graphics.DrawLine(pen,center.X,center.Y,center.X+5,center.Y+5);
    }
    public void ApplyTheme(Control root)
    {
        bool dark=IsDarkTheme;
        root.BackColor=dark?Color.FromArgb(30,42,34):Color.FromArgb(246,248,244);root.ForeColor=dark?Color.FromArgb(236,244,237):Color.FromArgb(32,51,39);
        if(root is Button && root.Tag?.ToString()=="selected")
        {
            root.BackColor=dark?Color.FromArgb(166,219,179):Color.FromArgb(56,107,74);
            root.ForeColor=dark?Color.FromArgb(26,51,33):Color.White;
        }
        if(root is NativeCategoryPager pager)pager.RefreshTheme(dark);
        if(root is NativeOrderPager ordersPager)ordersPager.RefreshTheme(dark);
        if(root is CategoryCard categoryCard){categoryCard.Dark=dark;categoryCard.Invalidate();}
        if(store.Language=="bo")root.Font=new Font(NativeFonts.Tibetan,root.Font.Size,root.Font.Style);
        foreach(Control child in root.Controls)ApplyTheme(child);
    }
    bool IsDarkTheme
    {
        get
        {
            if(store.Theme!="system")return store.Theme=="dark";
            using var personalize=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return personalize?.GetValue("AppsUseLightTheme") is int light&&light==0;
        }
    }
}

sealed class NativeDialog : Form
{
    readonly ShopStore store;
    readonly FlowLayoutPanel fields=new(){Dock=DockStyle.Fill,AutoScroll=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new(28,20,28,18)};
    readonly FlowLayoutPanel actions=new(){Dock=DockStyle.Bottom,Height=76,Padding=new(24,14,24,14),FlowDirection=FlowDirection.RightToLeft};
    readonly Label error=new(){Dock=DockStyle.Bottom,Height=48,Padding=new(28,3,28,3),ForeColor=Color.Firebrick};
    readonly Dictionary<string,Control> inputs=[];
    readonly Dictionary<string,string> files=[];
    readonly Button submit=new(){AutoSize=true,MinimumSize=new(100,40)};
    public Func<JsonObject,Task>? Submit;
    bool saving;
    public NativeDialog(ShopStore store,string title,(string Key,string Kind)[] list,JsonObject values)
    {
        this.store=store;Width=610;Height=title=="settings"?(store.DemoAvailable?740:510):700;MinimumSize=new(570,title=="settings"?470:500);StartPosition=FormStartPosition.CenterParent;Font=new("Segoe UI",10);
        Controls.Add(fields);Controls.Add(error);Controls.Add(actions);
        var cancel=new Button{Text=store.T("cancel"),AutoSize=true,MinimumSize=new(90,40)};
        cancel.Click+=(_,_)=>Close();submit.Text=store.T("save");actions.Controls.Add(submit);actions.Controls.Add(cancel);
        submit.Click+=async(_,_)=>await Save();FormClosing+=(_,e)=>{if(saving)e.Cancel=true;};
        Shown+=(_,_)=> (Owner as ShopWindow)?.ApplyTheme(this);
        Configure(title,list,values);
    }
    JsonObject Values()
    {
        var result=new JsonObject();
        foreach(var (key,input)in inputs)result[key]=input is ComboBox combo?((KeyValuePair<string,string>)combo.SelectedItem!).Key:input.Text;
        foreach(var (key,value)in files)result[key]=value;return result;
    }
    public void Configure(string title,(string Key,string Kind)[] list,JsonObject values)
    {
        Text=store.T(title);foreach(Control control in fields.Controls.Cast<Control>().ToArray())control.Dispose();inputs.Clear();files.Clear();error.Text="";
        fields.Controls.Add(new Label{Text=Text,AutoSize=true,Font=new("Segoe UI",21,FontStyle.Bold),Margin=new(0,0,0,18)});
        foreach(var (key,kind)in list)
        {
            if(kind=="heading")
            {
                fields.Controls.Add(new Label{Text=store.T(key),AutoSize=true,Font=new("Segoe UI",11,FontStyle.Bold),Margin=new(0,18,0,4)});continue;
            }
            fields.Controls.Add(new Label { Text=store.T(key),AutoSize=true,Margin=new(0,14,0,7) });
            if(kind=="avatar")
            {
                var pick=new Button { Text=store.T("uploadAvatar"),Width=470,Height=40 };
                pick.Click+=(_,_)=>
                {
                    using var file=new OpenFileDialog { Filter="PNG / JPEG / GIF|*.png;*.jpg;*.jpeg;*.gif",Multiselect=false };
                    if(file.ShowDialog(this)!=DialogResult.OK)return;
                    string mime=Path.GetExtension(file.FileName).ToLowerInvariant() switch {".png"=>"image/png",".gif"=>"image/gif",_=>"image/jpeg"};
                    files[key]="data:"+mime+";base64,"+Convert.ToBase64String(File.ReadAllBytes(file.FileName));pick.Text=Path.GetFileName(file.FileName);
                };
                fields.Controls.Add(pick);continue;
            }
            Control input;
            if(kind is "language" or "theme")
            {
                var combo=new ComboBox{Width=520,DropDownHeight=280,DropDownStyle=ComboBoxStyle.DropDownList,RightToLeft=RightToLeft.No,Margin=new(0,0,0,6),AccessibleName=store.T(key)};
                var choices=kind=="language"?ShopStore.Languages:new Dictionary<string,string>{["system"]=store.T("system"),["light"]=store.T("light"),["dark"]=store.T("dark")};
                combo.DataSource=choices.ToList();combo.DisplayMember="Value";combo.ValueMember="Key";combo.SelectedValue=S(values,key);input=combo;
            }
            else input=new TextBox{Width=520,Height=kind=="multiline"?85:35,Multiline=kind=="multiline",ScrollBars=kind=="multiline"?ScrollBars.Vertical:ScrollBars.None,ReadOnly=kind=="readonly",UseSystemPasswordChar=kind=="password",Text=S(values,key),Margin=new(0,0,0,6),AccessibleName=store.T(key)};
            inputs[key]=input;fields.Controls.Add(input);
            if(key=="uid")fields.Controls.Add(new Label{Text=store.T("uidHint"),AutoSize=true,MaximumSize=new(520,0),Margin=new(0,2,0,5)});
        }
        (Owner as ShopWindow)?.ApplyTheme(this);
    }
    async Task Save()
    {
        if(saving)return;saving=true;fields.Enabled=false;actions.Enabled=false;error.Text="";
        try { if(Submit!=null)await Submit(Values());saving=false;Close(); }
        catch(Exception failure) { error.Text=failure.Message; }
        finally { saving=false;fields.Enabled=true;actions.Enabled=true; }
    }
}

static class NativeFonts
{
    static readonly System.Drawing.Text.PrivateFontCollection Collection=new();
    static NativeFonts()
    {
        Collection.AddFontFile(Path.Combine(AppContext.BaseDirectory,"Assets","Fonts","NotoSerifTibetan.ttf"));
    }
    public static FontFamily Tibetan=>Collection.Families[0];
}
