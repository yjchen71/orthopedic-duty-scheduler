# 骨科值班系統

純前端網頁（`index.html`）＋ Supabase（資料庫與登入）＋ GitHub Pages（網站空間）。

- 醫師：開啟填寫連結（`…/#fill-2026-12`），選姓名、勾選不值班日期，免登入。
- 秘書：開啟網站首頁，用 Email／密碼登入，即時看到所有回覆，排班資料存在雲端。

## 一次性設定

1. **Supabase**（supabase.com，免費）：建立專案 →
   SQL Editor 貼上並執行 `supabase/schema.sql`。
2. Authentication → Providers → Email：**關閉 “Allow new users to sign up”**；
   Authentication → Users → *Add user* 建立秘書帳號（Email＋密碼）。
3. Project Settings → API：複製 *Project URL* 與 *anon public key*，填入 `config.js`。
4. **GitHub Pages**：repo Settings → Pages → Source 選擇分支（`/ (root)`），
   網址即為 `https://<帳號>.github.io/orthopedic-duty-scheduler/`。
5. 秘書登入後，「回覆狀況」頁會顯示本月填寫連結，轉發給醫師即可。

## 注意

- 醫師填寫目前以「姓名」識別、不需 PIN（任何人知道連結都能代填）。
  若需防止冒名，可再加每位醫師的個人 PIN。
- `anon key` 公開是正常的；資料安全靠 `schema.sql` 內的 Row Level Security。
