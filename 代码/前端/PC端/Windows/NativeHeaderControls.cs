// Created by Jobs. Header text stays on one baseline; the account menu owns the two session actions.
namespace Zhixu;

sealed class InlineSlogan : Control
{
    readonly string hero;
    readonly string introduction;
    public InlineSlogan(string hero,string introduction)
    {
        this.hero=hero;this.introduction=introduction;
        AccessibleName=hero+" "+introduction;AccessibleRole=AccessibleRole.StaticText;
        SetStyle(ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        var flags=TextFormatFlags.SingleLine|TextFormatFlags.NoPadding|TextFormatFlags.NoPrefix;
        float size=15;
        using var font=new Font(Font.FontFamily,size,FontStyle.Bold);
        using var subfont=new Font(Font.FontFamily,10);
        int heroWidth=TextRenderer.MeasureText(e.Graphics,hero,font,Size.Empty,flags).Width;
        int available=Math.Max(0,Width);
        if(heroWidth>available-35)
        {
            TextRenderer.DrawText(e.Graphics,hero+" "+introduction,subfont,ClientRectangle,ForeColor,flags|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
            return;
        }
        int titleHeight=TextRenderer.MeasureText(e.Graphics,hero,font,Size.Empty,flags).Height;
        int subtitleHeight=TextRenderer.MeasureText(e.Graphics,introduction,subfont,Size.Empty,flags).Height;
        int top=Math.Max(0,(Height-titleHeight)/2);
        TextRenderer.DrawText(e.Graphics,hero,font,new Point(0,top),ForeColor,flags);
        // One literal space follows the title; the smaller text shares its baseline.
        TextRenderer.DrawText(e.Graphics," "+introduction,subfont,new Rectangle(heroWidth,top+titleHeight-subtitleHeight,Math.Max(0,available-heroWidth),subtitleHeight),ForeColor,flags|TextFormatFlags.EndEllipsis);
    }
}

sealed class AccountMenuRenderer(bool dark) : ToolStripProfessionalRenderer
{
    readonly Color background=dark?Color.FromArgb(30,42,34):Color.White;
    readonly Color foreground=dark?Color.FromArgb(236,244,237):Color.FromArgb(32,51,39);
    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
    {
        e.Graphics.Clear(background);
    }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        bool exit=e.Item.Tag?.ToString()=="exit";
        Color fill=exit?(e.Item.Selected?Color.FromArgb(144,27,36):Color.FromArgb(177,35,46)):(e.Item.Selected?(dark?Color.FromArgb(53,75,60):Color.FromArgb(232,241,234)):background);
        using var brush=new SolidBrush(fill);e.Graphics.FillRectangle(brush,new Rectangle(Point.Empty,e.Item.Size));
    }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor=e.Item.Tag?.ToString()=="exit"?Color.White:foreground;
        base.OnRenderItemText(e);
    }
}
