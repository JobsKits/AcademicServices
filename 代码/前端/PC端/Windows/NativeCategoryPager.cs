// Created by Jobs. A single selection drives category cards, keyboard navigation and the paged content.
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace Zhixu;

static class NativeMotion
{
    [DllImport("user32.dll",SetLastError=true)]
    static extern bool SystemParametersInfo(uint action,uint parameter,out int enabled,uint flags);
    public static bool Reduced=>SystemInformation.HighContrast||SystemParametersInfo(0x1042,0,out int enabled,0)&&enabled==0;
}

sealed class CategoryCard : Button
{
    public string Category="all";
    public int Count;
    public bool ShowIcon=true;
    public bool Selected;
    public bool Dark;
    bool hovering;
    public CategoryCard()
    {
        FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;UseVisualStyleBackColor=false;
        AccessibleRole=AccessibleRole.PageTab;
        SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);
        Cursor=Cursors.Hand;TextAlign=ContentAlignment.MiddleLeft;
    }
    protected override void OnMouseEnter(EventArgs e){hovering=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovering=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        Color accent=Dark?Color.FromArgb(166,219,179):Color.FromArgb(56,107,74);
        Color ink=Selected?(Dark?Color.FromArgb(26,51,33):Color.White):ForeColor;
        Color surface=Selected?accent:(Dark?Color.FromArgb(38,53,43):Color.White);
        using var path=new GraphicsPath();
        var bounds=new Rectangle(1,1,Width-3,Height-3);int arc=24;
        path.AddArc(bounds.Left,bounds.Top,arc,arc,180,90);path.AddArc(bounds.Right-arc,bounds.Top,arc,arc,270,90);
        path.AddArc(bounds.Right-arc,bounds.Bottom-arc,arc,arc,0,90);path.AddArc(bounds.Left,bounds.Bottom-arc,arc,arc,90,90);path.CloseFigure();
        using var fill=new SolidBrush(surface);e.Graphics.FillPath(fill,path);
        using var edge=new Pen(Focused?accent:Color.FromArgb(Dark?65:220,Dark?82:226,Dark?69:219),Focused?2:1);
        if(!Selected||Focused)e.Graphics.DrawPath(edge,path);
        var flags=TextFormatFlags.EndEllipsis|TextFormatFlags.SingleLine|TextFormatFlags.NoPrefix;
        using var title=new Font(Font.FontFamily,12,FontStyle.Bold);
        using var countFont=new Font(Font.FontFamily,18,FontStyle.Bold);
        string count=Count.ToString();
        int countWidth=TextRenderer.MeasureText(e.Graphics,count,countFont,Size.Empty,flags).Width;
        int center=Height/2;
        if(ShowIcon)DrawIcon(e.Graphics,new Rectangle(16,center-10,20,20),ink);
        int titleStart=ShowIcon?45:18;
        TextRenderer.DrawText(e.Graphics,Text,title,new Rectangle(titleStart,0,Math.Max(0,Width-countWidth-titleStart-22),Height),ink,flags|TextFormatFlags.VerticalCenter);
        TextRenderer.DrawText(e.Graphics,count,countFont,new Rectangle(Width-countWidth-16,0,countWidth,Height),ink,flags|TextFormatFlags.VerticalCenter|TextFormatFlags.Right);
        if(hovering&&!Selected)
        {
            using var hover=new Pen(accent,1);e.Graphics.DrawPath(hover,path);
        }
        if(Focused)ControlPaint.DrawFocusRectangle(e.Graphics,new Rectangle(7,7,Width-14,Height-14),ink,surface);
    }
    void DrawIcon(Graphics graphics,Rectangle bounds,Color color)
    {
        using var pen=new Pen(color,1.6f){StartCap=LineCap.Round,EndCap=LineCap.Round,LineJoin=LineJoin.Round};
        int x=bounds.X,y=bounds.Y;
        switch(Category)
        {
            case "graduation":
                graphics.DrawLines(pen,[new(x,y+3),new(x+8,y+5),new(x+8,y+19),new(x,y+17),new(x,y+3)]);
                graphics.DrawLines(pen,[new(x+8,y+5),new(x+18,y+3),new(x+18,y+17),new(x+8,y+19)]);
                break;
            case "journal":
                graphics.DrawRectangle(pen,x+2,y+1,15,18);
                graphics.DrawLine(pen,x+6,y+6,x+13,y+6);graphics.DrawLine(pen,x+6,y+10,x+13,y+10);graphics.DrawLine(pen,x+6,y+14,x+11,y+14);
                break;
            case "editing":
                graphics.DrawPolygon(pen,[new(x+2,y+13),new(x+13,y+2),new(x+17,y+6),new(x+6,y+17),new(x+1,y+19)]);
                graphics.DrawLine(pen,x+11,y+4,x+15,y+8);
                break;
            default:
                for(int row=0;row<2;row++)for(int column=0;column<2;column++)graphics.DrawRectangle(pen,x+column*11,y+row*11,7,7);
                break;
        }
    }
}

sealed class NativeCategoryPager : Panel
{
    readonly ShopStore store;
    readonly string[] categories=["all","graduation","journal","editing"];
    readonly TableLayoutPanel strip=new(){Dock=DockStyle.Top,Height=82,ColumnCount=4,RowCount=1,Padding=new(0,0,0,12)};
    readonly Panel viewport=new(){Left=0,Top=90,Height=400,TabStop=true};
    readonly List<FlowLayoutPanel> pages=[];
    readonly List<CategoryCard> cards=[];
    readonly System.Windows.Forms.Timer animation=new(){Interval=15};
    readonly Action<string> onSelect;
    int selected;
    double position;
    Point? dragStart;
    DateTime started;
    double origin;
    bool layingOut;
    public NativeCategoryPager(ShopStore store,string current,Func<string,FlowLayoutPanel> makePage,Action<string> onSelect)
    {
        this.store=store;this.onSelect=onSelect;selected=Math.Max(0,Array.IndexOf(categories,current));position=selected;
        Controls.Add(viewport);Controls.Add(strip);
        for(int i=0;i<categories.Length;i++)
        {
            int index=i;strip.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,25));
            int count=store.Products.Count(p=>ShopStore.B(p,"active")&&(categories[i]=="all"||ShopStore.S(p,"category_id")==categories[i]));
            var card=new CategoryCard{Text=store.T(categories[i]),Category=categories[i],Count=count,Dock=DockStyle.Fill,Margin=new(i==0?0:6,0,i==3?0:6,0),AccessibleName=store.T(categories[i])+" "+count};
            card.Click+=(_,_)=>Select(index);
            card.KeyDown+=(_,e)=>{if(e.KeyCode is Keys.Left or Keys.Right){Select(Math.Clamp(selected+(e.KeyCode==Keys.Right?1:-1),0,3));cards[selected].Focus();e.Handled=true;}};
            strip.Controls.Add(card,i,0);cards.Add(card);
            var page=makePage(categories[i]);page.AutoSize=false;page.AutoScroll=false;page.WrapContents=true;page.Padding=new(0);page.Margin=new(0);
            pages.Add(page);viewport.Controls.Add(page);AttachDrag(page);
        }
        viewport.KeyDown+=(_,e)=>{if(e.KeyCode is Keys.Left or Keys.Right){Select(Math.Clamp(selected+(e.KeyCode==Keys.Right?1:-1),0,3));e.Handled=true;}};
        animation.Tick+=(_,_)=>Advance();
        SizeChanged+=(_,_)=>LayoutPages();
        Disposed+=(_,_)=>animation.Dispose();
        UpdateCards();
    }
    void AttachDrag(Control target)
    {
        if(target is not Button)
        {
            target.MouseDown+=(_,e)=>{if(e.Button==MouseButtons.Left)dragStart=target.PointToScreen(e.Location);};
            target.MouseUp+=(_,e)=>
            {
                if(dragStart is not {} start)return;
                dragStart=null;Point end=target.PointToScreen(e.Location);
                int distance=end.X-start.X;
                if(Math.Abs(distance)>65&&Math.Abs(distance)>Math.Abs(end.Y-start.Y))Select(Math.Clamp(selected+(distance<0?1:-1),0,3));
            };
        }
        foreach(Control child in target.Controls)AttachDrag(child);
    }
    public void RefreshTheme(bool dark)
    {
        foreach(var card in cards){card.Dark=dark;card.Invalidate();}
    }
    void Select(int index)
    {
        if(index==selected)return;
        selected=index;onSelect(categories[index]);UpdateCards();
        origin=position;started=DateTime.UtcNow;
        if(!NativeMotion.Reduced)animation.Start();
        else{position=selected;LayoutPages();}
    }
    void UpdateCards()
    {
        for(int i=0;i<cards.Count;i++)
        {
            cards[i].Selected=i==selected;
            cards[i].AccessibleDescription=store.T(categories[i]);
            cards[i].Invalidate();
        }
    }
    void Advance()
    {
        double progress=Math.Clamp((DateTime.UtcNow-started).TotalMilliseconds/240,0,1);
        position=origin+(selected-origin)*(1-Math.Pow(1-progress,3));
        LayoutPages();
        if(progress>=1)animation.Stop();
    }
    void LayoutPages()
    {
        if(layingOut||Width<10)return;layingOut=true;
        try
        {
            viewport.Width=Width;
            int maximumHeight=260;
            for(int i=0;i<pages.Count;i++)
            {
                var page=pages[i];page.Width=Width;
                foreach(Control child in page.Controls)
                {
                    if(child.Tag?.ToString()=="emptyCategory")child.Width=Math.Max(200,Width-20);
                }
                page.PerformLayout();
                int bottom=page.Controls.Count==0?240:page.Controls.Cast<Control>().Max(c=>c.Bottom+c.Margin.Bottom);
                page.Height=Math.Max(260,bottom+12);page.Left=(int)Math.Round((i-position)*Width);page.Top=0;
                if(i==selected)maximumHeight=page.Height;
            }
            viewport.Height=maximumHeight;Height=viewport.Bottom;
        }
        finally{layingOut=false;}
    }
}
