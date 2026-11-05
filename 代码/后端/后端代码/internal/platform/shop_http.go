// Created by Jobs on 2026年11月4日，星期三.
package platform

import (
	"context"
	"net/http"
	"strings"
)

func (a *API) publicShop(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != "GET" {
		return false
	}
	if r.URL.Path == "/api/v1/products" {
		products, err := a.engine.Products(r.Context(), false, r.URL.Query().Get("category_id"))
		if err != nil {
			fail(w, err)
		} else {
			respond(w, 200, map[string]any{"products": products, "payment_mode": a.engine.PaymentMode})
		}
		return true
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/products/") {
		id := strings.TrimPrefix(r.URL.Path, "/api/v1/products/")
		product, err := a.engine.Product(r.Context(), id)
		if err != nil {
			fail(w, err)
		} else {
			respond(w, 200, map[string]any{"product": product})
		}
		return true
	}
	return false
}
func (a *API) privateShop(w http.ResponseWriter, r *http.Request, ctx context.Context, u User) bool {
	if r.URL.Path == "/api/v1/admin/products" {
		if u.Role != "admin" {
			fail(w, denied())
			return true
		}
		if r.Method == "GET" {
			products, err := a.engine.Products(ctx, true, r.URL.Query().Get("category_id"))
			if err != nil {
				fail(w, err)
			} else {
				respond(w, 200, map[string]any{"products": products})
			}
			return true
		}
		if r.Method == "POST" {
			var in ProductInput
			if err := decode(w, r, &in); err != nil {
				fail(w, err)
				return true
			}
			product, err := a.engine.SaveProduct(ctx, u, "", r.Header.Get("Idempotency-Key"), in)
			if err != nil {
				fail(w, err)
			} else {
				respond(w, 201, map[string]any{"product": product})
			}
			return true
		}
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/admin/products/") && r.Method == "PUT" {
		var in ProductInput
		if err := decode(w, r, &in); err != nil {
			fail(w, err)
			return true
		}
		product, err := a.engine.SaveProduct(ctx, u, strings.TrimPrefix(r.URL.Path, "/api/v1/admin/products/"), r.Header.Get("Idempotency-Key"), in)
		if err != nil {
			fail(w, err)
		} else {
			respond(w, 200, map[string]any{"product": product})
		}
		return true
	}
	if r.URL.Path == "/api/v1/shop-orders" {
		if r.Method == "GET" {
			orders, err := a.engine.ShopOrders(ctx, u)
			if err != nil {
				fail(w, err)
			} else {
				respond(w, 200, map[string]any{"orders": orders, "payment_mode": a.engine.PaymentMode})
			}
			return true
		}
		if r.Method == "POST" {
			var in ShopCreateInput
			if err := decode(w, r, &in); err != nil {
				fail(w, err)
				return true
			}
			order, err := a.engine.CreateShopOrder(ctx, u, r.Header.Get("Idempotency-Key"), in)
			if err != nil {
				fail(w, err)
			} else {
				respond(w, 201, map[string]any{"order": order})
			}
			return true
		}
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/shop-orders/") {
		parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/v1/shop-orders/"), "/")
		if len(parts) == 1 && r.Method == "GET" {
			order, err := a.engine.ShopOrder(ctx, u, parts[0])
			if err != nil {
				fail(w, err)
			} else {
				respond(w, 200, map[string]any{"order": order})
			}
			return true
		}
		if len(parts) == 2 && parts[1] == "actions" && r.Method == "POST" {
			var in ShopAction
			if err := decode(w, r, &in); err != nil {
				fail(w, err)
				return true
			}
			order, err := a.engine.ActShopOrder(ctx, u, parts[0], r.Header.Get("Idempotency-Key"), in)
			if err != nil {
				fail(w, err)
			} else {
				respond(w, 200, map[string]any{"order": order})
			}
			return true
		}
	}
	if strings.HasPrefix(r.URL.Path, "/api/v1/shop-operations/") && r.Method == "GET" {
		receipt, product, order, err := a.engine.ShopOperation(ctx, u, strings.TrimPrefix(r.URL.Path, "/api/v1/shop-operations/"))
		if err != nil {
			fail(w, err)
		} else {
			out := map[string]any{"operation": map[string]any{"status": "succeeded", "resource_type": receipt.ResourceType, "resource_id": receipt.ResourceID, "action": receipt.Action, "created_at": receipt.Created}}
			if product != nil {
				out["product"] = product
			}
			if order != nil {
				out["order"] = order
			}
			respond(w, 200, out)
		}
		return true
	}
	return false
}
