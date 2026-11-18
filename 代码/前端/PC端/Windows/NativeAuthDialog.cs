// Created by Jobs. Three independent native cards keep their own drafts and share no persisted password.
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using Microsoft.Win32;
using static Zhixu.ShopStore;

namespace Zhixu;

sealed class NativeAuthDialog : Form
{
    readonly ShopStore store;
    readonly Panel rail=new(){Dock=DockStyle.Left,Width=160,Padding=new(14)};
    readonly Panel viewport=new(){Dock=DockStyle.Fill,Padding=new(0)};
    readonly Dictionary<string,AuthCard> cards=[];
    readonly Dictionary<string,Button> switches=[];
    readonly System.Windows.Forms.Timer transition=new(){Interval=16};
    readonly Stopwatch clock=new();
    string mode="login";
    string? outgoing;
    bool busy;
    Color surface,background,foreground,secondary,accent,activeBackground;
    public bool SignedIn { get; private set; }
    public NativeAuthDialog(ShopStore store,string initial="login")
    {
        this.store=store;
        Text=store.T(initial);Size=new(760,660);MinimumSize=new(680,660);MaximumSize=new(950,660);
        StartPosition=FormStartPosition.CenterParent;Font=new(store.Language=="bo"?NativeFonts.Tibetan:new FontFamily("Segoe UI"),10);
        Controls.Add(viewport);Controls.Add(rail);
        int y=112;
        foreach(var key in new[]{"login","register","forgotPassword"})
        {
            var next=key;
            var button=new Button{Text=store.T(key),Location=new(10,y),Size=new(140,70),FlatStyle=FlatStyle.Flat,TextAlign=ContentAlignment.MiddleLeft,Padding=new(12,0,5,0),AccessibleName=store.T(key),TabIndex=rail.Controls.Count};
            button.FlatAppearance.BorderSize=0;button.Click+=(_,_)=>Switch(next);rail.Controls.Add(button);switches[key]=button;y+=84;
            var card=CreateCard(key);cards[key]=card;viewport.Controls.Add(card);
        }
        transition.Tick+=(_,_)=>TickTransition();
        FormClosing+=(_,e)=>{if(busy)e.Cancel=true;};
        FormClosed+=(_,_)=>{transition.Dispose();SystemEvents.UserPreferenceChanged-=OnPreference;};
        SystemEvents.UserPreferenceChanged+=OnPreference;
        Resize+=(_,_)=>{transition.Stop();outgoing=null;LayoutCards();};
        ApplyPalette();Switch(initial,false);
    }
    AuthCard CreateCard(string key)
    {
        var card=new AuthCard{Mode=key,AutoScroll=true,Padding=new(26,20,24,18)};
        var flow=new FlowLayoutPanel{AutoSize=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new(0),Margin=new(0)};card.Flow=flow;card.Controls.Add(flow);
        card.AccessibleName=store.T(key);
        flow.Controls.Add(TextLabel(store.T(key=="login"?"loginHint":key=="register"?"authRegisterIntro":"authResetIntro"),10));
        if(key=="login"&&store.DemoAvailable)
        {
            flow.Controls.Add(TextLabel(store.T("demoRole"),10,true));
            var identities=new ComboBox{Width=405,DropDownStyle=ComboBoxStyle.DropDownList,DataSource=new[]{new KeyValuePair<string,string>("customer",store.T("demoBuyer")),new("customer2",store.T("demoBuyer2"))}.ToList(),DisplayMember="Value",ValueMember="Key",Margin=new(0,2,0,7)};
            card.Identity=identities;flow.Controls.Add(identities);
            flow.Controls.Add(TextLabel(store.T("demoPrefilled"),9));
            identities.SelectedValueChanged+=(_,_)=>{if(card.Inputs.TryGetValue("account",out var account)){account.Text=identities.SelectedValue?.ToString()??"customer";card.Inputs["password"].Text="demo-customer";((NativePasswordInput)card.Inputs["password"]).Revealed=true;}};
        }
        var fields=key=="login"?new[]{("account","text"),("password","password")}:key=="register"?new[]{("email","text"),("code","text"),("username","text"),("password","password"),("confirmPassword","password")}:new[]{("email","text"),("code","text"),("password","password"),("confirmPassword","password")};
        foreach(var (field,kind)in fields)
        {
            flow.Controls.Add(TextLabel(store.T(field),10,true));
            Control input=kind=="password"?new NativePasswordInput(store,key=="login"&&store.DemoAvailable?"demo-customer":"",key=="login"&&store.DemoAvailable):new TextBox{Width=405,AutoSize=false,Height=42,Text=key=="login"&&store.DemoAvailable?"customer":"",Margin=new(0,1,0,8)};
            input.AccessibleName=store.T(field);card.Inputs[field]=input;flow.Controls.Add(input);
            input.KeyDown+=(_,e)=>{if(e.KeyCode==Keys.Enter){e.SuppressKeyPress=true;_ = Submit(card);}};
        }
        if(key!="login")
        {
            var send=ActionButton("sendCode",async()=>await SendCode(card),false);flow.Controls.Add(send);
        }
        card.Error=TextLabel("",10);card.Error.ForeColor=Color.Firebrick;flow.Controls.Add(card.Error);
        card.Submit=ActionButton(key=="login"?"login":key=="register"?"createAccount":"resetPassword",async()=>await Submit(card),true);flow.Controls.Add(card.Submit);
        var link=new LinkLabel{Text=store.T(key=="login"?"register":"backToSignIn"),AutoSize=true,Margin=new(0,12,0,5)};link.LinkClicked+=(_,_)=>Switch(key=="login"?"register":"login");flow.Controls.Add(link);
        if(key=="login")
        {
            var reset=new LinkLabel{Text=store.T("forgotPassword"),AutoSize=true,Margin=new(0,3,0,5)};reset.LinkClicked+=(_,_)=>Switch("forgotPassword");flow.Controls.Add(reset);
        }
        card.Cancel=ActionButton("cancel",()=>{Close();return Task.CompletedTask;},false);flow.Controls.Add(card.Cancel);
        return card;
    }
    Label TextLabel(string text,float size,bool bold=false)=>new(){Text=text,AutoSize=true,MaximumSize=new(405,0),MinimumSize=new(0,22),Font=new(Font.FontFamily,size,bold?FontStyle.Bold:FontStyle.Regular),Margin=new(0,4,0,7)};
    Button ActionButton(string key,Func<Task> action,bool primary)
    {
        var button=new Button{Text=store.T(key),Width=405,Height=40,Margin=new(0,6,0,2),FlatStyle=FlatStyle.Flat,Tag=primary?"primary":null};button.FlatAppearance.BorderSize=0;button.Click+=async(_,_)=>await action();return button;
    }
    JsonObject Values(AuthCard card){var values=new JsonObject();foreach(var (key,input)in card.Inputs)values[key]=input.Text;return values;}
    async Task SendCode(AuthCard card)
    {
        if(busy)return;SetBusy(true);card.Error.Text="";
        try{var result=await store.Authentication("/auth/email-code",new JsonObject{["email"]=card.Inputs["email"].Text,["purpose"]=card.Mode=="register"?"register":"reset_password"});card.Error.Text=S(result,"demo_code").Length>0?store.T("demoCode")+": "+S(result,"demo_code"):store.T("codeSent");}
        catch(Exception error){card.Error.Text=error.Message;}
        finally{SetBusy(false);}
    }
    async Task Submit(AuthCard card)
    {
        if(busy||card.Mode!=mode)return;SetBusy(true);card.Error.Text="";
        try
        {
            var values=Values(card);
            if(card.Mode=="login")
            {
                await store.Login(values);
                if(store.User==null)throw new ApiException(401,store.T("signInFirst"));
                foreach(var input in card.Inputs.Values.OfType<NativePasswordInput>())input.Text="";SignedIn=true;SetBusy(false);DialogResult=DialogResult.OK;Close();
            }
            else
            {
                if(S(values,"password")!=S(values,"confirmPassword"))throw new ApiException(422,store.T("required"));
                values["confirm_password"]=S(values,"confirmPassword");values.Remove("confirmPassword");
                await store.Authentication(card.Mode=="register"?"/auth/register":"/auth/reset-password",values);
                var nextMessage=store.T(card.Mode=="register"?"accountCreated":"passwordReset");
                cards["login"].Inputs["account"].Text=card.Inputs["email"].Text;
                cards["login"].Inputs["password"].Text="";
                card.Inputs["password"].Text="";card.Inputs["confirmPassword"].Text="";
                SetBusy(false);Switch("login");cards["login"].Error.Text=nextMessage;
            }
        }
        catch(Exception error){card.Error.Text=error.Message;}
        finally{if(!IsDisposed)SetBusy(false);}
    }
    void SetBusy(bool value){busy=value;rail.Enabled=!value;foreach(var card in cards.Values)card.Enabled=!value;}
    void Switch(string next,bool animate=true)
    {
        if(busy)return;transition.Stop();var previous=mode;mode=next;Text=store.T(next);ApplyPalette();
        foreach(var (key,card)in cards){card.Visible=key==next||key==previous;card.TabStop=key==next;card.Enabled=key==next;}
        outgoing=previous!=next?previous:null;
        if(!animate||outgoing==null||ReducedMotion()){outgoing=null;LayoutCards();cards[next].SelectNextControl(null,true,true,true,false);return;}
        cards[previous].Location=new(0,0);cards[next].Location=new(viewport.ClientSize.Width+16,0);cards[next].BringToFront();clock.Restart();transition.Start();
    }
    void LayoutCards(){int route=0;foreach(var key in new[]{"login","register","forgotPassword"}){switches[key].Bounds=new Rectangle(10,6+(rail.ClientSize.Height-12)*route/3,140,(rail.ClientSize.Height-12)/3-10);route++;}foreach(var (key,card)in cards){card.Size=viewport.ClientSize;card.Location=key==mode?Point.Empty:new(viewport.ClientSize.Width+16,0);card.Visible=key==mode;card.Flow.Width=Math.Max(360,viewport.ClientSize.Width-52);foreach(Control control in card.Flow.Controls)if(control is not LinkLabel){control.MaximumSize=new(Math.Max(350,viewport.ClientSize.Width-58),0);if(control is TextBox or NativePasswordInput or ComboBox or Button)control.Width=Math.Max(350,viewport.ClientSize.Width-58);}}AcceptButton=cards[mode].Submit;CancelButton=cards[mode].Cancel;}
    void TickTransition(){double t=Math.Min(1,clock.Elapsed.TotalMilliseconds/700),e=t*t*(3-2*t);int width=viewport.ClientSize.Width+16;cards[mode].Location=new((int)(width*(1-e)),0);if(outgoing!=null)cards[outgoing].Location=new((int)(-width*e),0);if(t>=1){transition.Stop();outgoing=null;LayoutCards();cards[mode].SelectNextControl(null,true,true,true,false);}}
    void OnPreference(object sender,UserPreferenceChangedEventArgs e){if(!IsDisposed)BeginInvoke(()=>{ApplyPalette();if(ReducedMotion()){transition.Stop();outgoing=null;LayoutCards();}});}
    void ApplyPalette()
    {
        bool dark=store.Theme=="dark";
        if(store.Theme=="system"){using var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");dark=key?.GetValue("AppsUseLightTheme") is int n&&n==0;}
        background=dark?Color.FromArgb(24,36,29):Color.FromArgb(244,247,241);surface=dark?Color.FromArgb(32,47,38):Color.White;foreground=dark?Color.FromArgb(236,245,237):Color.FromArgb(31,57,40);secondary=dark?Color.FromArgb(190,210,196):Color.FromArgb(76,102,84);accent=dark?Color.FromArgb(170,220,181):Color.FromArgb(48,99,64);activeBackground=dark?Color.FromArgb(61,89,69):Color.FromArgb(218,234,217);
        if(SystemInformation.HighContrast){background=surface=SystemColors.Window;foreground=secondary=accent=SystemColors.WindowText;activeBackground=SystemColors.Highlight;}
        BackColor=background;rail.BackColor=background;
        void Paint(Control control){control.BackColor=surface;control.ForeColor=foreground;if(control is LinkLabel link)link.LinkColor=accent;if(control is Button button&&button.Tag?.ToString()=="primary"){button.BackColor=accent;button.ForeColor=dark?Color.FromArgb(24,42,29):Color.White;}foreach(Control child in control.Controls)Paint(child);}
        foreach(var card in cards.Values)Paint(card);
        foreach(Control child in rail.Controls){child.ForeColor=foreground;child.BackColor=background;}
        foreach(var (key,button)in switches){button.BackColor=key==mode?activeBackground:background;button.ForeColor=key==mode?accent:secondary;button.Font=new(Font.FontFamily,10,key==mode?FontStyle.Bold:FontStyle.Regular);button.AccessibleDescription=key==mode?store.T(key):"";}
    }
    static bool ReducedMotion()=>SystemInformation.HighContrast||SystemParametersInfo(0x1042,0,out int enabled,0)&&enabled==0;
    [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool SystemParametersInfo(uint action,uint param,out int value,uint flags);
    sealed class AuthCard : Panel
    {
        public string Mode="";
        public FlowLayoutPanel Flow=null!;
        public ComboBox? Identity;
        public Label Error=null!;
        public Button Submit=null!;
        public Button Cancel=null!;
        public readonly Dictionary<string,Control> Inputs=[];
    }
}
