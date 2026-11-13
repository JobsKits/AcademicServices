// Created by Jobs on 2026年11月5日，星期四.
package platform

import (
	"context"
	"encoding/base64"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"unicode"
)

const bannerImageLimit = 2 << 20

type Banner struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Image     string `json:"image"`
	TargetURL string `json:"target_url"`
	Active    bool   `json:"active"`
	SortOrder int    `json:"sort_order"`
	Version   int    `json:"version"`
	Created   string `json:"created_at"`
	Updated   string `json:"updated_at"`
}
type BannerInput struct {
	Title           string `json:"title"`
	Image           string `json:"image"`
	TargetURL       string `json:"target_url"`
	Active          bool   `json:"active"`
	SortOrder       int    `json:"sort_order"`
	ExpectedVersion int    `json:"expected_version"`
}

func safeWebURL(value string, httpsOnly bool) bool {
	if len(value) > 4096 || strings.IndexFunc(value, unicode.IsControl) >= 0 || strings.Contains(value, "\\") {
		return false
	}
	u, err := url.Parse(value)
	return err == nil && u.IsAbs() && u.Hostname() != "" && u.User == nil && (u.Scheme == "https" || !httpsOnly && u.Scheme == "http")
}
func validShopImage(value string, maxBytes int, allowEmpty bool) error {
	if value == "" && allowEmpty {
		return nil
	}
	if value == "" || len(value) > base64.StdEncoding.EncodedLen(maxBytes)+64 {
		return invalid("图片为空或超过大小限制")
	}
	if strings.HasPrefix(value, "data:image/png;base64,") || strings.HasPrefix(value, "data:image/jpeg;base64,") || strings.HasPrefix(value, "data:image/webp;base64,") {
		parts := strings.SplitN(value, ",", 2)
		decoded, err := base64.StdEncoding.DecodeString(parts[1])
		mediaType := strings.TrimSuffix(strings.TrimPrefix(parts[0], "data:"), ";base64")
		if err == nil && len(decoded) > 0 && len(decoded) <= maxBytes && http.DetectContentType(decoded) == mediaType {
			return nil
		}
		return invalid("图片须为大小有效的PNG、JPEG或WebP")
	}
	if safeWebURL(value, true) {
		return nil
	}
	u, err := url.Parse(value)
	if err == nil && u.Scheme == "" && u.Host == "" && u.Path != "" && u.RawQuery == "" && u.Fragment == "" && !strings.HasPrefix(value, "//") && !strings.Contains(u.Path, "..") && !strings.ContainsAny(value, "\\\r\n\x00") {
		return nil
	}
	return invalid("图片须为HTTPS、打包资源地址或PNG/JPEG/WebP图片data URL")
}
func (e *Engine) Banners(ctx context.Context, all bool) ([]*Banner, error) {
	out := []*Banner{}
	err := e.Store.View(ctx, func(s *State) error {
		if !all && len(s.Banners) == 0 {
			out = defaultBanners()
			return nil
		}
		for _, b := range s.Banners {
			if all || b.Active {
				copy := *b
				out = append(out, &copy)
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	slices.SortFunc(out, func(a, b *Banner) int {
		if a.SortOrder < b.SortOrder {
			return -1
		}
		if a.SortOrder > b.SortOrder {
			return 1
		}
		return strings.Compare(a.ID, b.ID)
	})
	return out, nil
}
func (e *Engine) SaveBanner(ctx context.Context, u User, id, key string, in BannerInput) (*Banner, error) {
	if u.Role != "admin" {
		return nil, denied()
	}
	if err := checkKey(key); err != nil {
		return nil, err
	}
	h := hash(struct {
		Path  string
		Input BannerInput
	}{"banners/" + id, in})
	var out *Banner
	err := e.Store.Update(ctx, func(s *State) error {
		if r, ok, err := shopRepeat(s, u, key, h); ok {
			if err != nil {
				return err
			}
			b := s.Banners[r.ResourceID]
			if b == nil {
				return missing()
			}
			copy := *b
			out = &copy
			return nil
		}
		if strings.TrimSpace(in.Title) == "" || len([]rune(in.Title)) > 120 || in.SortOrder < 0 || in.SortOrder > 1000000 {
			return invalid("轮播标题限120字，排序须为0至1000000")
		}
		if err := validShopImage(in.Image, bannerImageLimit, false); err != nil {
			return err
		}
		if in.TargetURL != "" && !safeWebURL(in.TargetURL, false) {
			return invalid("轮播点击地址须为HTTP(S)绝对地址或留空")
		}
		now := e.Now()
		created := timestamp(now)
		version := 1
		bannerID := id
		if id != "" {
			b := s.Banners[id]
			if b == nil {
				return missing()
			}
			if b.Version != in.ExpectedVersion {
				return &Problem{409, "version_conflict", "轮播已变化，请刷新后核对"}
			}
			created = b.Created
			version = b.Version + 1
		} else {
			bannerID = uuid()
		}
		if s.Banners == nil {
			s.Banners = map[string]*Banner{}
		}
		b := &Banner{ID: bannerID, Title: strings.TrimSpace(in.Title), Image: in.Image, TargetURL: in.TargetURL, Active: in.Active, SortOrder: in.SortOrder, Version: version, Created: created, Updated: timestamp(now)}
		s.Banners[bannerID] = b
		shopEvent(s, u, bannerID, "save_banner", b.Title, "", "", now)
		s.ShopReceipts[receiptName(u, key)] = ShopReceipt{h, "banner", bannerID, "save_banner", u.ID, timestamp(now)}
		copy := *b
		out = &copy
		return nil
	})
	return out, err
}
