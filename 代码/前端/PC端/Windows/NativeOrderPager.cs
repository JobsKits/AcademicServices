// Created by Jobs. Order state cards and content pages share one selection and live counts.
using static Zhixu.ShopStore;

namespace Zhixu;

sealed class OrderPagerSurface : Panel
{
    public OrderPagerSurface(){TabStop=true;SetStyle(ControlStyles.Selectable,true);}
    protected override bool IsInputKey(Keys keys)=>keys is Keys.Left or Keys.Right or Keys.PageUp or Keys.PageDown||base.IsInputKey(keys);
}

sealed class NativeOrderPager : Panel
{
    readonly string[] states=["all","pending_payment","pending_completion","pending_review","completed","cancelled"];
    readonly Panel scroller=new(){Dock=DockStyle.Top,Height=99,AutoScroll=true,TabStop=false};
    readonly FlowLayoutPanel strip=new(){Left=0,Top=0,Height=76,WrapContents=false,FlowDirection=FlowDirection.LeftToRight,Margin=new(0),Padding=new(0)};
    readonly OrderPagerSurface viewport=new(){Left=0,Top=110};
    readonly List<FlowLayoutPanel> pages=[];
    readonly List<CategoryCard> cards=[];
    readonly Action<string> onSelect;
    readonly System.Windows.Forms.Timer animation=new(){Interval=15};
    int selected;
    int availableHeight=460;
    double position,origin;
    DateTime started;
    Point? dragStart;
    bool layingOut;
    public NativeOrderPager(ShopStore store,string current,Func<string,FlowLayoutPanel> makePage,Action<string> onSelect)
    {
        this.onSelect=onSelect;selected=Math.Max(0,Array.IndexOf(states,current));position=selected;
        Controls.Add(viewport);Controls.Add(scroller);scroller.Controls.Add(strip);
        for(int index=0;index<states.Length;index++)
        {
            int destination=index;
            int count=store.Orders.Count(order=>states[index]=="all"||S(order,"status")==states[index]);
            var card=new CategoryCard{Text=store.T(states[index]),Count=count,ShowIcon=false,Width=174,Height=72,Margin=new(0,0,12,0),AccessibleName=store.T(states[index])+" ("+count+")"};
            card.Click+=(_,_)=>Select(destination);
            card.KeyDown+=(_,e)=>
            {
                if(e.KeyCode is Keys.Left or Keys.Right or Keys.PageUp or Keys.PageDown)
                {
                    Select(Math.Clamp(selected+(e.KeyCode is Keys.Right or Keys.PageDown?1:-1),0,states.Length-1));cards[selected].Focus();e.Handled=true;e.SuppressKeyPress=true;
                }
            };
            cards.Add(card);strip.Controls.Add(card);
            var page=makePage(states[index]);page.AutoSize=false;page.AutoScroll=false;page.WrapContents=false;page.FlowDirection=FlowDirection.TopDown;page.Padding=new(0);page.Margin=new(0);
            pages.Add(page);viewport.Controls.Add(page);AttachGesture(page);
        }
        strip.Width=cards.Sum(card=>card.Width+card.Margin.Horizontal);
        scroller.AutoScrollMinSize=new(strip.Width,0);
        viewport.KeyDown+=(_,e)=>
        {
            if(e.KeyCode is Keys.Left or Keys.Right or Keys.PageUp or Keys.PageDown)
            {
                Select(Math.Clamp(selected+(e.KeyCode is Keys.Right or Keys.PageDown?1:-1),0,states.Length-1));e.Handled=true;e.SuppressKeyPress=true;
            }
        };
        AttachGesture(viewport,false);
        animation.Tick+=(_,_)=>Advance();SizeChanged+=(_,_)=>LayoutPages();
        Disposed+=(_,_)=>animation.Dispose();UpdateCards();
    }
    public void SetAvailableSize(int width,int height)
    {
        availableHeight=Math.Max(0,height);Width=width;LayoutPages();
    }
    public void RefreshTheme(bool dark)
    {
        foreach(var card in cards){card.Dark=dark;card.Invalidate();}
    }
    void AttachGesture(Control control,bool recursive=true)
    {
        if(control is Button or TextBox)return;
        control.MouseDown+=(_,e)=>{if(e.Button==MouseButtons.Left){dragStart=control.PointToScreen(e.Location);if(control==viewport)viewport.Focus();}};
        control.MouseUp+=(_,e)=>
        {
            if(dragStart is not {} start)return;
            dragStart=null;Point end=control.PointToScreen(e.Location);
            int horizontal=end.X-start.X,vertical=end.Y-start.Y;
            if(Math.Abs(horizontal)>65&&Math.Abs(horizontal)>Math.Abs(vertical))Select(Math.Clamp(selected+(horizontal<0?1:-1),0,states.Length-1));
        };
        if(recursive)foreach(Control child in control.Controls)AttachGesture(child);
    }
    void Select(int index)
    {
        if(index==selected)return;
        selected=index;onSelect(states[index]);UpdateCards();
        origin=position;started=DateTime.UtcNow;
        if(NativeMotion.Reduced){position=selected;LayoutPages();}
        else animation.Start();
    }
    void UpdateCards()
    {
        for(int i=0;i<cards.Count;i++){cards[i].Selected=i==selected;cards[i].Invalidate();}
        EnsureSelectionVisible();
    }
    void EnsureSelectionVisible()
    {
        int visibleLeft=-scroller.AutoScrollPosition.X;
        var card=cards[selected];
        if(card.Left<visibleLeft)scroller.AutoScrollPosition=new(card.Left,0);
        else if(card.Right>visibleLeft+scroller.ClientSize.Width)scroller.AutoScrollPosition=new(Math.Max(0,card.Right-scroller.ClientSize.Width+6),0);
    }
    void Advance()
    {
        double fraction=Math.Clamp((DateTime.UtcNow-started).TotalMilliseconds/240,0,1);
        position=origin+(selected-origin)*(1-Math.Pow(1-fraction,3));LayoutPages();
        if(fraction>=1)animation.Stop();
    }
    void LayoutPages()
    {
        if(layingOut||Width<10)return;layingOut=true;
        try
        {
            viewport.Width=Width;
            EnsureSelectionVisible();
            int minimumHeight=Math.Max(270,availableHeight-viewport.Top);
            int selectedHeight=minimumHeight;
            for(int i=0;i<pages.Count;i++)
            {
                var page=pages[i];page.Width=Width;
                bool empty=page.Controls.Count==1&&page.Controls[0].Tag?.ToString()=="orderDataEmpty";
                foreach(Control card in page.Controls)
                {
                    if(empty)
                    {
                        card.Width=Width;card.Margin=new(0,Math.Max(0,(minimumHeight-card.Height)/2),0,0);
                    }
                    else FitCard(card,Width);
                }
                page.PerformLayout();
                int bottom=empty?minimumHeight:page.Controls.Cast<Control>().Select(c=>c.Bottom+c.Margin.Bottom).DefaultIfEmpty(minimumHeight).Max();
                page.Height=empty?minimumHeight:Math.Max(minimumHeight,bottom+8);page.Top=0;page.Left=(int)Math.Round((i-position)*Width);
                if(i==selected)selectedHeight=page.Height;
            }
            viewport.Height=selectedHeight;Height=viewport.Bottom;
        }
        finally{layingOut=false;}
    }
    static void FitCard(Control card,int width)
    {
        int outer=Math.Max(300,width-card.Margin.Horizontal);
        card.MinimumSize=new(outer,0);card.MaximumSize=new(outer,0);card.Width=outer;
        int inner=Math.Max(260,outer-card.Padding.Horizontal-8);
        foreach(Control field in card.Controls)
        {
            if(field is Label){field.MinimumSize=new(inner,35);field.MaximumSize=new(inner,0);field.Width=inner;}
            else if(field is TextBox or FlowLayoutPanel)field.Width=inner;
        }
        card.PerformLayout();
    }
}
