// Created by Jobs on 2026年11月5日，星期四.
package platform

import (
	"embed"
	"encoding/base64"
)

//go:embed BannerAssets/*.png
var bannerAssets embed.FS

func defaultBanners() []*Banner {
	rows := []struct{ id, title string }{{"graduation", "毕业论文"}, {"journal", "普刊"}, {"editing", "编译"}}
	result := make([]*Banner, 0, len(rows))
	for i, row := range rows {
		data, err := bannerAssets.ReadFile("BannerAssets/" + row.id + ".png")
		if err != nil {
			panic("packaged banner missing: " + row.id)
		}
		result = append(result, &Banner{ID: "seed-" + row.id, Title: row.title, Image: "data:image/png;base64," + base64.StdEncoding.EncodeToString(data), Active: true, SortOrder: i, Version: 1, Created: "2026-11-05T00:00:00Z", Updated: "2026-11-05T00:00:00Z"})
	}
	return result
}

func defaultBannerMap() map[string]*Banner {
	result := make(map[string]*Banner, 3)
	for _, banner := range defaultBanners() {
		result[banner.ID] = banner
	}
	return result
}
