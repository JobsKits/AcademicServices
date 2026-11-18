// Created by Jobs. The native textbox remains the only password value; the eye is drawn by GDI+.
using System.Drawing.Drawing2D;
using System.ComponentModel;
using System.Diagnostics.CodeAnalysis;

namespace Zhixu;

sealed class NativePasswordInput : UserControl
{
    readonly TextBox input = new() { BorderStyle=BorderStyle.None, Dock=DockStyle.Fill, UseSystemPasswordChar=true };
    readonly EyeButton eye = new() { Dock=DockStyle.Right, Width=40, TabStop=true };
    readonly ShopStore store;
    [AllowNull]
    public override string Text { get => input?.Text??""; set { if(input!=null)input.Text=value??""; } }
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public bool Revealed
    {
        get => !input.UseSystemPasswordChar;
        set { input.UseSystemPasswordChar=!value; eye.Revealed=value; eye.AccessibleName=store.T(value?"hidePassword":"showPassword"); eye.Invalidate(); }
    }
    public NativePasswordInput(ShopStore store, string value="", bool revealed=false)
    {
        this.store=store;
        Width=410;Height=42;Padding=new(11,9,0,7);BorderStyle=BorderStyle.FixedSingle;
        Controls.Add(input);Controls.Add(eye);Text=value;Revealed=revealed;
        input.TextChanged+=(_,_)=>OnTextChanged(EventArgs.Empty);
        eye.Click+=(_,_)=>Revealed=!Revealed;
        input.KeyDown+=(_,e)=>{if(e.Alt&&e.KeyCode==Keys.V){Revealed=!Revealed;e.Handled=true;e.SuppressKeyPress=true;}};
        BackColorChanged+=(_,_)=>{input.BackColor=BackColor;eye.BackColor=BackColor;};
        ForeColorChanged+=(_,_)=>{input.ForeColor=ForeColor;eye.ForeColor=ForeColor;};
    }
    public void FocusEditor() => input.Focus();
    sealed class EyeButton : Button
    {
        public bool Revealed;
        public EyeButton() { FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;AccessibleRole=AccessibleRole.PushButton; }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            using var pen=new Pen(ForeColor,1.6f);
            using var pupil=new SolidBrush(ForeColor);
            using var path=new GraphicsPath();
            float x=(Width-24)/2f,y=(Height-18)/2f;
            path.AddBezier(x,y+9,x+6,y-1,x+18,y-1,x+24,y+9);
            path.AddBezier(x+24,y+9,x+18,y+19,x+6,y+19,x,y+9);
            e.Graphics.DrawPath(pen,path);e.Graphics.FillEllipse(pupil,x+9,y+6,6,6);
            if(Revealed)e.Graphics.DrawLine(pen,x+1,y+1,x+23,y+17);
            if(Focused)ControlPaint.DrawFocusRectangle(e.Graphics,ClientRectangle);
        }
    }
}
