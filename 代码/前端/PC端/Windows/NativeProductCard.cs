// Created by Jobs. Product navigation covers the card without turning a horizontal drag into a click.
namespace Zhixu;

sealed class NativeProductCard : FlowLayoutPanel
{
    readonly Action navigate;
    Point? pressed;
    public NativeProductCard(Action navigate)
    {
        this.navigate=navigate;
        FlowDirection=FlowDirection.TopDown;WrapContents=false;AutoSize=true;AutoSizeMode=AutoSizeMode.GrowAndShrink;
        MinimumSize=new(300,0);MaximumSize=new(300,0);Width=300;Margin=new(8);Padding=new(16);BorderStyle=BorderStyle.FixedSingle;
        Tag="card";Cursor=Cursors.Hand;TabStop=true;AccessibleRole=AccessibleRole.Link;
        SetStyle(ControlStyles.Selectable,true);
        BindClick(this);
    }
    public void BindChildren()
    {
        foreach(Control child in Controls)BindClick(child);
    }
    void BindClick(Control target)
    {
        // Dedicated buttons retain their own native action and never bubble a second navigation.
        if(target is Button)return;
        target.Cursor=Cursors.Hand;
        target.MouseDown+=(_,e)=>{if(e.Button==MouseButtons.Left){pressed=target.PointToScreen(e.Location);Focus();}};
        target.MouseClick+=(_,e)=>
        {
            if(e.Button!=MouseButtons.Left||pressed is not {} start)return;
            pressed=null;Point end=target.PointToScreen(e.Location);
            if(Math.Abs(end.X-start.X)<8&&Math.Abs(end.Y-start.Y)<8)navigate();
        };
        foreach(Control child in target.Controls)BindClick(child);
    }
    protected override bool IsInputKey(Keys keyData)
    {
        return keyData is Keys.Enter or Keys.Space||base.IsInputKey(keyData);
    }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if(e.KeyCode is Keys.Enter or Keys.Space){e.Handled=true;e.SuppressKeyPress=true;navigate();}
        else base.OnKeyDown(e);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if(Focused)ControlPaint.DrawFocusRectangle(e.Graphics,new Rectangle(4,4,Width-8,Height-8),ForeColor,BackColor);
    }
    protected override void OnGotFocus(EventArgs e){base.OnGotFocus(e);Invalidate();}
    protected override void OnLostFocus(EventArgs e){base.OnLostFocus(e);Invalidate();}
}
