// Created by Jobs. Native image selection keeps the original frames alive for GIF playback.
using System.Text.Json.Nodes;
using static Zhixu.ShopStore;

namespace Zhixu;

sealed class NativeAvatarPicture : PictureBox
{
    MemoryStream? imageStream;
    public NativeAvatarPicture()
    {
        SizeMode=PictureBoxSizeMode.Zoom;
        TabStop=false;
    }
    public void SetEncoded(string encoded)
    {
        if(!encoded.StartsWith("data:image/",StringComparison.Ordinal))return;
        int separator=encoded.IndexOf(',');
        if(separator<0)return;
        var stream=new MemoryStream(Convert.FromBase64String(encoded[(separator+1)..]));
        try
        {
            var image=Image.FromStream(stream,true,true);
            Image?.Dispose();imageStream?.Dispose();
            imageStream=stream;Image=image;
        }
        catch
        {
            stream.Dispose();throw;
        }
    }
    protected override void Dispose(bool disposing)
    {
        if(disposing)
        {
            Image?.Dispose();Image=null;imageStream?.Dispose();imageStream=null;
        }
        base.Dispose(disposing);
    }
}

sealed class NativeAvatarDialog : Form
{
    readonly ShopStore store;
    readonly NativeAvatarPicture preview=new(){Width=116,Height=116,Margin=new(0,0,0,16)};
    readonly Label error=new(){AutoSize=true,MaximumSize=new(520,0),ForeColor=Color.Firebrick,Margin=new(0,14,0,0)};
    readonly FlowLayoutPanel body=new(){Dock=DockStyle.Fill,AutoScroll=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new(28)};
    readonly FlowLayoutPanel actions=new(){Dock=DockStyle.Bottom,Height=76,Padding=new(22,14,22,14),FlowDirection=FlowDirection.RightToLeft};
    string selection="";
    bool saving;
    public NativeAvatarDialog(ShopStore store)
    {
        this.store=store;Text=store.T("chooseAvatar");Width=620;Height=650;MinimumSize=new(580,560);
        StartPosition=FormStartPosition.CenterParent;Font=new("Segoe UI",10);MinimizeBox=false;MaximizeBox=false;
        Controls.Add(body);Controls.Add(actions);
        body.Controls.Add(new Label{Text=Text,AutoSize=true,Font=new("Segoe UI",20,FontStyle.Bold),Margin=new(0,0,0,18)});
        try
        {
            preview.Image=Image.FromFile(Path.Combine(AppContext.BaseDirectory,"Assets","icon.png"));
            preview.SetEncoded(S(store.User,"avatar_url"));
        }
        catch(Exception failure)when(failure is IOException or ArgumentException or FormatException){ }
        body.Controls.Add(preview);
        body.Controls.Add(new Label{Text=store.T("presetAvatars"),AutoSize=true,Font=new("Segoe UI",11,FontStyle.Bold),Margin=new(0,6,0,10)});
        var presets=new FlowLayoutPanel{Width=520,Height=165,AutoScroll=true,WrapContents=true,Margin=new(0,0,0,14)};
        string directory=Path.Combine(AppContext.BaseDirectory,"Assets","Avatars");
        if(Directory.Exists(directory))
        {
            foreach(string path in Directory.EnumerateFiles(directory).Where(p=>Path.GetExtension(p).ToLowerInvariant() is ".png" or ".jpg" or ".jpeg" or ".gif").Order())
            {
                var choice=new Button{Width=72,Height=72,FlatStyle=FlatStyle.Flat,Margin=new(0,0,10,10),AccessibleName=store.T("presetAvatars")+" "+Path.GetFileNameWithoutExtension(path),ImageAlign=ContentAlignment.MiddleCenter};
                choice.FlatAppearance.BorderSize=1;
                using(var original=Image.FromFile(path))choice.Image=new Bitmap(original,new Size(60,60));
                choice.Disposed+=(_,_)=>choice.Image?.Dispose();
                choice.Click+=(_,_)=>SelectImage(path);
                presets.Controls.Add(choice);
            }
        }
        body.Controls.Add(presets);
        var local=new Button{Text=store.T("localImage"),AutoSize=true,MinimumSize=new(160,42),Margin=new(0,4,0,8)};
        local.Click+=(_,_)=>
        {
            using var file=new OpenFileDialog{Filter="PNG / JPEG / GIF|*.png;*.jpg;*.jpeg;*.gif",Multiselect=false};
            if(file.ShowDialog(this)==DialogResult.OK)SelectImage(file.FileName);
        };
        body.Controls.Add(local);
        body.Controls.Add(new Label{Text=store.T("nativeAvatarFormats"),AutoSize=true,MaximumSize=new(520,0),Margin=new(0,2,0,0)});
        body.Controls.Add(error);
        var save=new Button{Text=store.T("save"),AutoSize=true,MinimumSize=new(100,42)};
        var cancel=new Button{Text=store.T("cancel"),AutoSize=true,MinimumSize=new(100,42)};
        cancel.Click+=(_,_)=>Close();
        save.Click+=async(_,_)=>
        {
            if(saving||selection.Length==0)return;
            saving=true;body.Enabled=false;actions.Enabled=false;error.Text="";
            try
            {
                await store.SaveProfile(new JsonObject{["avatar"]=selection});
                saving=false;Close();
            }
            catch(Exception failure){error.Text=failure.Message;}
            finally{saving=false;body.Enabled=true;actions.Enabled=true;}
        };
        actions.Controls.Add(save);actions.Controls.Add(cancel);AcceptButton=save;CancelButton=cancel;
        FormClosing+=(_,e)=>{if(saving)e.Cancel=true;};
        Shown+=(_,_)=> (Owner as ShopWindow)?.ApplyTheme(this);
    }
    void SelectImage(string path)
    {
        try
        {
            const int maximumBytes=20*1024*1024;
            using var input=File.OpenRead(path);
            if(input.Length==0||input.Length>maximumBytes)throw new InvalidDataException();
            using var contents=new MemoryStream((int)input.Length);
            byte[] buffer=new byte[81920];
            int received;
            while((received=input.Read(buffer,0,buffer.Length))>0)
            {
                // Enforce the bound while reading as well, in case the selected file grows.
                if(contents.Length+received>maximumBytes)throw new InvalidDataException();
                contents.Write(buffer,0,received);
            }
            byte[] bytes=contents.ToArray();
            string mime;
            if(bytes.AsSpan().StartsWith(new byte[]{137,80,78,71,13,10,26,10}))mime="image/png";
            else if(bytes.AsSpan().StartsWith("GIF87a"u8)||bytes.AsSpan().StartsWith("GIF89a"u8))mime="image/gif";
            else if(bytes.AsSpan().StartsWith(new byte[]{255,216,255}))mime="image/jpeg";
            else throw new InvalidDataException();
            string encoded="data:"+mime+";base64,"+Convert.ToBase64String(bytes);
            preview.SetEncoded(encoded);selection=encoded;error.Text="";
        }
        catch(Exception failure)when(failure is IOException or ArgumentException or FormatException or UnauthorizedAccessException)
        {
            error.Text=store.T("invalidDesktopAvatar");
        }
    }
}
