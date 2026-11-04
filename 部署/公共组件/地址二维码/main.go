// Deployment URL cards are generated locally; addresses never leave this process.
package main

import (
	"bytes"
	"flag"
	"fmt"
	"html/template"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	qrcode "github.com/skip2/go-qrcode"
)

type entries []string

func (e *entries) String() string     { return strings.Join(*e, ",") }
func (e *entries) Set(s string) error { *e = append(*e, s); return nil }

type card struct {
	Label, URL, SVG string
	Image           template.HTML
	Bitmap          [][]bool
}
type page struct {
	Title, Generated string
	Cards            []card
	Expired          bool
}

const pageHTML = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:;"><title>{{.Title}}</title><style>body{font:16px system-ui,sans-serif;background:#eef2f7;color:#172236;margin:0;padding:24px}main{max-width:940px;margin:auto}h1{font-size:26px}.cards{display:flex;flex-wrap:wrap;gap:24px}.card{background:white;border:1px solid #d5dce5;border-radius:16px;padding:24px;flex:1 1 300px;min-width:0}.qr{background:#fff;max-width:360px;margin:auto}.qr svg{width:100%;height:auto;display:block}a{color:#0759bd;overflow-wrap:anywhere}textarea{width:100%;box-sizing:border-box;min-height:72px;padding:12px;font:14px monospace;margin:16px 0}small{color:#48566b}.notice{border-left:4px solid #c56c00;padding:12px;background:#fff5de}</style><main><h1>{{.Title}}</h1>{{if .Expired}}<p class="notice">本次部署已结束，此页二维码已失效。请重新部署并使用新页面。</p>{{else}}<p class="notice">扫码打开对应入口，再按页面要求登录。二维码只包含下面的访问地址。临时地址仅在本次服务与隧道运行期间有效；重新部署后请使用新码。</p><div class="cards">{{range .Cards}}<section class="card"><h2>{{.Label}}</h2><div class="qr">{{.Image}}</div><textarea readonly aria-label="{{.Label}}完整地址">{{.URL}}</textarea><a href="{{.URL}}" rel="noreferrer">打开{{.Label}}</a> · <a href="{{.SVG}}" download>保存二维码 SVG</a></section>{{end}}</div>{{end}}<p><small>生成时间：{{.Generated}}。地址与二维码生成成功不代表公网验收通过；请用手机实际验证登录、写入与刷新重读。</small></p></main></html>`

// Reject credential-bearing or wildcard addresses before displaying or encoding anything.
func parseCard(raw string) (card, error) {
	label, address, ok := strings.Cut(raw, "|")
	if !ok || strings.TrimSpace(label) == "" || strings.ContainsAny(raw, "\r\n\t\x1b") {
		return card{}, fmt.Errorf("入口必须为 标题|完整HTTP地址，不能含控制字符")
	}
	u, err := url.Parse(address)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.Opaque != "" {
		return card{}, fmt.Errorf("入口必须为完整HTTP或HTTPS地址")
	}
	if u.User != nil {
		return card{}, fmt.Errorf("入口不能含账户凭据")
	}
	query, err := url.ParseQuery(u.RawQuery)
	if err != nil {
		return card{}, fmt.Errorf("入口查询参数无效")
	}
	fragment, _ := url.ParseQuery(u.Fragment)
	for _, fields := range []url.Values{query, fragment} {
		for key := range fields {
			switch strings.ToLower(key) {
			case "token", "access_token", "refresh_token", "password", "passwd", "secret", "api_key", "apikey", "authorization", "credential", "session", "sessionid", "code", "signature", "sig":
				return card{}, fmt.Errorf("入口不能含认证或签名参数")
			}
		}
	}
	if u.Hostname() == "0.0.0.0" || u.Hostname() == "::" {
		return card{}, fmt.Errorf("监听通配地址不能作为访问入口")
	}
	qr, err := qrcode.New(address, qrcode.Medium)
	if err != nil {
		return card{}, fmt.Errorf("二维码内容过长或无法编码")
	}
	return card{Label: label, URL: address, Bitmap: qr.Bitmap()}, nil
}

// Keep the encoder's four-module quiet zone and use integer-aligned black cells.
func svgFor(c card) string {
	n := len(c.Bitmap)
	var b strings.Builder
	fmt.Fprintf(&b, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" shape-rendering="crispEdges" role="img" aria-label="访问二维码"><rect width="100%%" height="100%%" fill="white"/><path fill="black" d="`, n, n, n*8, n*8)
	for y, row := range c.Bitmap {
		for x, dark := range row {
			if dark {
				fmt.Fprintf(&b, "M%d %dh1v1h-1z", x, y)
			}
		}
	}
	b.WriteString(`"/></svg>`)
	return b.String()
}

// Only owned ordinary output files may be atomically replaced.
func writeOutput(dir, name string, data []byte) error {
	destination := filepath.Join(dir, name)
	if st, err := os.Lstat(destination); err == nil && !st.Mode().IsRegular() {
		return fmt.Errorf("拒绝替换非普通输出文件")
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".qr-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err = tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err = tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), destination)
}

// ANSI fixes the foreground/background; narrow and plain terminals use the local page.
func terminalCard(out io.Writer, c card, width int, ansi bool) {
	fmt.Fprintf(out, "\n%s\n%s\n", c.Label, c.URL)
	_, noColor := os.LookupEnv("NO_COLOR")
	if !ansi || noColor || width < len(c.Bitmap)+2 {
		fmt.Fprintln(out, "终端未显示方块码，请打开下方本地二维码页面。")
		return
	}
	for y := 0; y < len(c.Bitmap); y += 2 {
		fmt.Fprint(out, "\x1b[30;47m")
		for x := range c.Bitmap[y] {
			top := c.Bitmap[y][x]
			bottom := y+1 < len(c.Bitmap) && c.Bitmap[y+1][x]
			switch {
			case top && bottom:
				fmt.Fprint(out, "█")
			case top:
				fmt.Fprint(out, "▀")
			case bottom:
				fmt.Fprint(out, "▄")
			default:
				fmt.Fprint(out, " ")
			}
		}
		fmt.Fprintln(out, "\x1b[0m")
	}
}

func run(args []string, out io.Writer) error {
	fs := flag.NewFlagSet("deployqr", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	var values entries
	dir := fs.String("output-dir", "", "本次运行独占的输出目录")
	title := fs.String("title", "部署访问入口", "页面标题")
	width := fs.Int("terminal-width", 0, "终端列数；0仅生成文件")
	ansi := fs.Bool("ansi", false, "终端允许黑白ANSI二维码")
	expire := fs.Bool("expire", false, "将本次页面标记失效")
	fs.Var(&values, "entry", "入口标题|完整URL，可重复")
	if err := fs.Parse(args); err != nil {
		return fmt.Errorf("二维码参数无效")
	}
	if *dir == "" || fs.NArg() != 0 || (!*expire && len(values) == 0) {
		return fmt.Errorf("需要 --output-dir 和至少一个 --entry")
	}
	var cards []card
	for _, raw := range values {
		c, err := parseCard(raw)
		if err != nil {
			return err
		}
		cards = append(cards, c)
	}
	// Validate before writing; do not follow a symlink output directory.
	if st, err := os.Lstat(*dir); err == nil && (!st.IsDir() || st.Mode()&os.ModeSymlink != 0) {
		return fmt.Errorf("二维码目录不能为符号链接或文件")
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(*dir, 0700); err != nil {
		return err
	}
	for i := range cards {
		cards[i].SVG = fmt.Sprintf("%02d.svg", i+1)
		cards[i].Image = template.HTML(svgFor(cards[i]))
		if err := writeOutput(*dir, cards[i].SVG, []byte(cards[i].Image)); err != nil {
			return err
		}
		n := len(cards[i].Bitmap) * 8
		img := image.NewGray(image.Rect(0, 0, n, n))
		for y := 0; y < n; y++ {
			for x := 0; x < n; x++ {
				shade := color.Gray{Y: 255}
				if cards[i].Bitmap[y/8][x/8] {
					shade.Y = 0
				}
				img.SetGray(x, y, shade)
			}
		}
		var raster bytes.Buffer
		if err := png.Encode(&raster, img); err != nil {
			return err
		}
		if err := writeOutput(*dir, fmt.Sprintf("%02d.png", i+1), raster.Bytes()); err != nil {
			return err
		}
	}
	t, err := template.New("page").Parse(pageHTML)
	if err != nil {
		return err
	}
	var b bytes.Buffer
	if err := t.Execute(&b, page{Title: *title, Generated: time.Now().Format(time.RFC3339), Cards: cards, Expired: *expire}); err != nil {
		return err
	}
	if err := writeOutput(*dir, "index.html", b.Bytes()); err != nil {
		return err
	}
	if !*expire {
		for _, c := range cards {
			terminalCard(out, c, *width, *ansi)
		}
		abs, _ := filepath.Abs(filepath.Join(*dir, "index.html"))
		fmt.Fprintf(out, "\n本地二维码页面（浏览器打开）：\n%s\n", abs)
	}
	return nil
}
func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "二维码未生成：", err)
		os.Exit(1)
	}
}
