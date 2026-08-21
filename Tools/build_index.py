#!/usr/bin/env python3
"""
Builds Resources/free-mac-index.json — a best-effort complete index of the
FREE, native-Mac apps in the Mac App Store.

Method: the iTunes Search API is the only public endpoint that reaches into
the full Mac catalog, but a single query is relevance-truncated (even under
the 200-result cap), so we enumerate with a wide net of terms:
  - every single letter a-z and digit 0-9
  - every letter bigram aa..zz (676 queries)
  - trigrams for bigrams that hit the 200-result cap

Results are deduped by trackId; only entries with price == 0 and
kind == "mac-software" (native Mac apps) are kept.

Output JSON shape:
  { "built": iso8601, "country": cc, "terms": n, "total": n, "apps": [ {id,name,developer,icon,genre,rating,ratingCount,minOS,blurb,url}, ... ] }

The consuming app re-verifies every entry live (in-app purchases check)
before showing it, so staleness of this index never breaks the guarantee.
"""
import json
import string
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

COUNTRY = "us"
DELAY = 0.35          # polite spacing between API calls
CAP = 200
OUT = "Resources/free-mac-index.json"

UA = {"User-Agent": "FreeAppStoreIndexBuilder/1.0 (personal catalog build)"}
seen = {}             # trackId -> entry dict
terms_run = 0
errors = 0


def search(term, retries=2):
    global errors
    url = ("https://itunes.apple.com/search?term=" + urllib.parse.quote(term)
           + f"&entity=macSoftware&country={COUNTRY}&limit={CAP}")
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except Exception as e:
            if attempt == retries:
                errors += 1
                print(f"    !! giving up on {term!r}: {e}", file=sys.stderr)
                return {"resultCount": 0, "results": []}
            time.sleep(1.5 * (attempt + 1))
    return {"resultCount": 0, "results": []}


def add_results(results):
    added = 0
    for r in results:
        tid = r.get("trackId")
        if not tid or tid in seen:
            continue
        if r.get("kind") != "mac-software":
            continue
        if r.get("price") != 0:
            continue
        desc = (r.get("description") or "").split("\n")[0][:220]
        seen[tid] = {
            "id": str(tid),
            "name": r.get("trackName") or r.get("trackCensoredName") or "",
            "developer": r.get("artistName") or r.get("sellerName") or "",
            "icon": r.get("artworkUrl100") or r.get("artworkUrl512") or "",
            "genre": r.get("primaryGenreName") or "",
            "rating": round(r.get("averageUserRating") or 0, 2),
            "ratingCount": r.get("userRatingCount") or 0,
            "minOS": r.get("minimumOsVersion") or "",
            "blurb": desc,
            "url": r.get("trackViewUrl") or "",
        }
        added += 1
    return added


def run_term(term, refine_on_cap=False):
    """Run one search term; returns whether it hit the result cap."""
    global terms_run
    d = search(term)
    terms_run += 1
    n = d.get("resultCount", 0)
    new = add_results(d.get("results", []))
    print(f"  {term:<5} -> {n:3d} results, +{new} new (index: {len(seen)})")
    time.sleep(DELAY)
    return refine_on_cap and n >= CAP


def main():
    t0 = time.time()
    singles = list(string.ascii_lowercase) + list(string.digits)
    bigrams = [a + b for a in string.ascii_lowercase for b in string.ascii_lowercase]

    print(f"Phase 1: {len(singles)} singles")
    capped = []
    for t in singles:
        if run_term(t, refine_on_cap=True):
            capped.append(t)

    print(f"Phase 2: {len(bigrams)} bigrams")
    for t in bigrams:
        if run_term(t, refine_on_cap=True):
            capped.append(t)

    # Phase 3: capped bigrams get trigram refinement (common prefix splits)
    trigrams = [t + c for t in capped for c in string.ascii_lowercase]
    print(f"Phase 3: {len(trigrams)} trigrams (from {len(capped)} capped terms)")
    for t in trigrams:
        run_term(t)

    apps = sorted(seen.values(), key=lambda a: a["ratingCount"], reverse=True)
    out = {
        "built": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "country": COUNTRY,
        "terms": terms_run,
        "errors": errors,
        "total": len(apps),
        "apps": apps,
    }
    with open(OUT, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    dt = time.time() - t0
    print(f"\nDone in {dt/60:.1f} min: {terms_run} terms, {errors} errors")
    print(f"Index: {len(apps)} free native Mac apps -> {OUT}")


if __name__ == "__main__":
    main()
