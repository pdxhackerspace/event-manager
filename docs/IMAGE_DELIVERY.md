# Image Delivery

How event images reach the browser, and the things that have caused them to
silently fail to load.

## Table of Contents

- [How Images Are Served](#how-images-are-served)
- [Preview Variants](#preview-variants)
- [Rate Limiting Interaction](#rate-limiting-interaction)
- [Reverse Proxy Expectations](#reverse-proxy-expectations)
- [Server Capacity](#server-capacity)
- [Backfilling Variants](#backfilling-variants)
- [Diagnosing Missing Images](#diagnosing-missing-images)
- [Optional: Offloading File Delivery to nginx](#optional-offloading-file-delivery-to-nginx)

---

## How Images Are Served

Images are Active Storage attachments on `EventImage`, stored on local disk
(`storage/`, mounted into the `web` and `sidekiq` containers). There is no S3 and
no asset CDN.

Attachments are served in **proxy mode**, set in `config/application.rb`:

```ruby
config.active_storage.resolve_model_to_route = :rails_storage_proxy
```

This matters more than it looks. Active Storage's default is *redirect* mode,
where `image_tag attachment` produces a URL that returns a `302` to a second,
short-lived signed URL that then serves the bytes. That means:

- **Two requests per image** instead of one.
- **URLs expire** (`service_urls_expire_in`, five minutes by default), so
  nothing downstream can cache them for long.

Proxy mode serves the bytes directly from a stable URL with
`Cache-Control: public, max-age=<far future>`. Because the URL ends in the
original filename's extension, Cloudflare caches it under its default rules, so
repeat views never reach Puma at all.

Note that this makes any attachment URL publicly cacheable by anyone holding the
URL. The signed ID in the path is unguessable, which is the same trust model
Active Storage uses for redirect mode, but it means a banner on a private event
should not be treated as a secret.

A few call sites still generate redirect URLs deliberately with
`rails_blob_url`: Open Graph tags (`app/helpers/seo_helper.rb`) and Slack/social
posts. Those need absolute URLs for external crawlers and are low volume.

## Preview Variants

Banner originals are typically 1-3 MB at 1200x400. Rendering those into an 80x40
thumbnail wastes almost all of the bytes downloaded, so `EventImage` declares
scaled variants:

```ruby
PREVIEW_VARIANTS = {
  thumb: { resize_to_limit: [300, 300] },
  card: { resize_to_limit: [800, 800] }
}.freeze
```

`preprocessed: true` means Sidekiq generates them when an image is uploaded, so
no page request ever waits on ImageMagick.

Views should use the helpers in `app/helpers/event_images_helper.rb` rather than
`image_tag` directly. They pick the variant, add `loading="lazy"`, and fall back
to the original for blobs ImageMagick cannot transform:

| Helper | Variant | Use for |
|---|---|---|
| `event_image_thumbnail_tag` | `:thumb` (300px) | Pickers, list rows, form previews |
| `event_image_card_tag` | `:card` (800px) | Event card grids |
| `image_tag` | original | Full-width hero banners only |

**Sidekiq needs the storage volume.** `docker-compose.yml` mounts
`./storage:/app/storage` into both `web` and `sidekiq`. Without it, variant
generation and `Spectra6BannerJob` fail because the worker cannot read uploads.

## Rate Limiting Interaction

The general `req/ip` throttle in `config/initializers/rack_attack.rb` **must**
keep exempting `/rails/active_storage`. An event with ten pooled images renders
far more image requests than page requests, and counting them against a
per-visitor page budget produces 429 responses. A 429 on an `<img>` renders as a
blank or broken image with no error surfaced anywhere in the UI, and it clears on
its own when the window rolls over, which makes it look like an intermittent
storage or network problem rather than rate limiting.

See [SECURITY.md](SECURITY.md#rate-limiting-with-cloudflare) for the client IP
resolution rules that go with this.

## Reverse Proxy Expectations

Deployment is Cloudflare in front of Nginx Proxy Manager in front of Puma.

**Required:**

- Forward `X-Forwarded-For` and `X-Forwarded-Proto`. Nginx Proxy Manager does
  this by default; `config.assume_ssl = true` depends on it.
- Leave `CF-Connecting-IP` intact. Rate limiting keys on it.

**Worth checking in the proxy host's Advanced tab if large uploads or images
misbehave:**

```nginx
client_max_body_size 10m;
proxy_read_timeout 120s;
proxy_buffering off;
```

`proxy_buffering off` keeps nginx from buffering whole image responses to disk
before forwarding them. The longer read timeout gives Puma room when several
large images are requested at once.

**Do not** put a rate limit or connection limit on the proxy host for
`/rails/active_storage` paths, for the same reason Rack::Attack exempts them.

## Server Capacity

Proxy mode streams every image byte through a Puma request thread. `config/puma.rb`
therefore runs multiple workers outside development:

- `WEB_CONCURRENCY` (default 3) processes
- `RAILS_MAX_THREADS` (default 5) threads each

That is 15 concurrent requests and 15 database connections. Raising
`WEB_CONCURRENCY` raises both, so check PostgreSQL's `max_connections` before
going much higher, and remember Sidekiq holds 5 more.

Browsers open many parallel connections per origin over HTTP/2, so a page with
dozens of uncached images can still queue behind the thread pool. Cached variants
are what actually keep this cheap, not raw worker count.

## Backfilling Variants

Images uploaded before variants were preprocessed have no variants stored. The
first request for one generates it on demand, which is slow but correct. To
generate them ahead of time:

```bash
docker compose exec web bin/rails images:preprocess_variants
```

Run this after deploying a change to `EventImage::PREVIEW_VARIANTS`.

## Diagnosing Missing Images

Images that appear on some page loads and not others are almost never lost files.
Work through these in order:

1. **Check for throttling.** Missing images plus 429s is rate limiting:

   ```bash
   docker compose logs web | grep 'Rack::Attack'
   ```

2. **Check the actual status codes** in the browser's Network tab, filtered to
   images. `429` is rate limiting, `502`/`504` is Puma saturation or a proxy
   timeout, `404` is a genuinely missing blob.

3. **Confirm the files exist:**

   ```bash
   docker compose exec web bin/rails runner \
     'ActiveStorage::Blob.find_each { |b| puts b.key unless b.service.exist?(b.key) }'
   ```

4. **Check whether variants are being generated.** A backed-up or crashing
   Sidekiq leaves previews to be generated inline on request:

   ```bash
   docker compose logs sidekiq | tail -50
   ```

## Optional: Offloading File Delivery to nginx

Proxy mode plus Cloudflare caching keeps Puma out of the hot path for repeat
requests, which is enough for this deployment. If first-request throughput ever
becomes the bottleneck, nginx can serve the files itself:

1. Mount `./storage` into the Nginx Proxy Manager container.
2. Add an internal location to the proxy host's advanced config:

   ```nginx
   location /internal-storage/ {
     internal;
     alias /storage/;
   }
   ```

3. Set `config.action_dispatch.x_sendfile_header = "X-Accel-Redirect"` and
   `config.active_storage.draw_routes` accordingly in
   `config/environments/production.rb`.

This is more moving parts and couples the proxy to the app's storage layout, so
prefer caching until measurements say otherwise.
