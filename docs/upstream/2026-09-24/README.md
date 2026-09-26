# Upstream snapshot — 2026-09-24

This is a local, read-only record of the GitHub state for [`JK3Y/NPS-Browser-macOS`](https://github.com/JK3Y/NPS-Browser-macOS). It does not close or otherwise change upstream issues or pull requests.

- Retrieval began: **2026-09-24T13:08:42Z** (UTC; see [`retrieval.txt`](retrieval.txt) for start and finish).
- Recheck time: see [`raw/recheck/time.txt`](raw/recheck/time.txt).
- Open issue count: **25** (issues API records with pull-request records excluded).
- Open PR count: **1**, PR **#66**; it is not a draft.
- Count evidence: [`counts.txt`](counts.txt), from a fresh API recheck. Raw responses are under [`raw/`](raw/).
- Human-readable tracking: [`disposition.md`](disposition.md). It records named checks observed in the local test run and keeps unexercised reports **Unverified**.

## Captured data

- `raw/issues/pages/`: paginated open-issues API responses. The GitHub issues endpoint also returns PR records; the derived `raw/open-issues.json` filters those out and retains all issue bodies and metadata.
- `raw/pulls/pages/`: paginated open-PR API responses, including PR body, state, draft flag and source URL.
- `raw/issues/comments-paginated/<number>/` and `raw/pulls/{comments-paginated,reviews-paginated,review-comments-paginated}/<number>/`: every page of issue conversation comments, PR conversation comments, PR reviews and inline review comments, each preserved as the direct JSON API response.
- `raw/pulls/patches/66.patch`: PR #66's two-commit unified patch, refreshed from the API at the time recorded in `retrieval.txt`.
- `raw/pulls/patches/66.patch.json`: preserved JSON PR response that was initially stored under the `.patch` filename.
- `raw/recheck/`: fresh issue and PR listings used to recheck counts after capture.
- `raw/issues/comments/<number>.json` and `raw/pulls/{comments,reviews,review-comments}/<number>.json`: first-pass page-one responses, retained as collected; the `*-paginated` page sets are the complete authoritative comment/review captures.
- `source-endpoints.txt`: listing endpoint templates. Individual issue and PR `html_url` values and API URLs are also present in the JSON records.

The source endpoints are public GitHub REST API resources for `issues?state=open`, `pulls?state=open`, per-issue comments, PR reviews, PR inline comments, and the PR `.patch` representation. All list/comment/review calls request pages of 100 and preserve each page separately. The snapshot records content as retrieved; it does not assert that upstream has not changed since the stated retrieval time.
