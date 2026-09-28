#!/usr/bin/env python3
"""App Store Connect for RSS Quick: TestFlight status, build numbers, and distribution.

Run by .github/workflows/ios-release.yml and ios-testflight-status.yml on a GitHub runner, where
the App Store Connect API key comes from repository secrets. It can be run by hand on a Mac too,
with the same three environment variables:

    ASC_KEY_ID        the 10-character key ID
    ASC_ISSUER_ID     the issuer UUID
    ASC_KEY_PATH      path to AuthKey_<id>.p8

Commands:

    asc.py status
        Every build with its version, processing state, external state and Beta App Review
        state; the App Store versions; the TestFlight groups and their public links.

    asc.py next-build-number
        One more than the highest build number App Store Connect has for the app, across every
        version. Build numbers then only ever go up, so a new build can never collide with an
        old one - including builds uploaded by hand from a Mac with release-testflight.sh.

    asc.py distribute --version 1.3.0 --build 7 [--group External] [--whats-new FILE]
        Waits for that build to finish processing, sets its "What to Test" text, adds it to the
        external group (creating the group, with a public link, if there is none), and submits
        it for Beta App Review.

Nothing here prints the key or the token. Needs PyJWT, cryptography and requests.
"""

import argparse
import os
import sys
import time

import jwt
import requests

BUNDLE_ID = "com.kellylford.rssquick"
API = "https://api.appstoreconnect.apple.com/v1"
DEFAULT_GROUP = "External"


class Client:
    def __init__(self):
        key_path = os.environ["ASC_KEY_PATH"]
        with open(key_path, encoding="utf-8") as f:
            self._key = f.read()
        self._key_id = os.environ["ASC_KEY_ID"]
        self._issuer = os.environ["ASC_ISSUER_ID"]
        self._session = requests.Session()
        self._token_expires = 0

    def _authorise(self):
        # Tokens may live 20 minutes at most. Refreshed well before that, because distribute
        # can wait longer than a token lasts for a build to finish processing.
        now = int(time.time())
        if now < self._token_expires - 120:
            return
        self._token_expires = now + 15 * 60
        token = jwt.encode(
            {"iss": self._issuer, "iat": now, "exp": self._token_expires, "aud": "appstoreconnect-v1"},
            self._key, algorithm="ES256", headers={"kid": self._key_id, "typ": "JWT"})
        self._session.headers["Authorization"] = f"Bearer {token}"

    def request(self, method, path, **kwargs):
        self._authorise()
        response = self._session.request(method, API + path, timeout=60, **kwargs)
        if response.status_code >= 400:
            detail = ""
            try:
                errors = response.json().get("errors", [])
                detail = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errors)
            except ValueError:
                detail = response.text[:500]
            raise ApiError(response.status_code, f"{method} {path} -> {response.status_code} {detail}")
        return response.json() if response.content else {}

    def get(self, path, **params):
        return self.request("GET", path, params=params)


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def app_id(client):
    # The filter is not guaranteed to be an exact match, so the result is checked.
    apps = client.get("/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    app = next((a for a in apps if a["attributes"].get("bundleId") == BUNDLE_ID), None)
    if app is None:
        sys.exit(f"No app in App Store Connect has the bundle ID {BUNDLE_ID}.")
    return app["id"], app["attributes"]["name"]


def builds(client, app, **extra):
    params = {"filter[app]": app, "sort": "-uploadedDate", "limit": 200}
    params.update(extra)
    return client.get("/builds", **params)


# ── status ──────────────────────────────────────────────────────────────────


def status(client, _args):
    app, name = app_id(client)
    print(f"{name} ({BUNDLE_ID})")

    result = builds(client, app, limit=25,
                    include="preReleaseVersion,buildBetaDetail,betaAppReviewSubmission")
    included = {(i["type"], i["id"]): i["attributes"] for i in result.get("included", [])}

    def related(build, name, kind):
        data = build["relationships"].get(name, {}).get("data")
        return included.get((kind, data["id"]), {}) if data else {}

    print("\nTestFlight builds, newest first:")
    print("  version (build) | processing | external testing | Beta App Review | uploaded")
    for build in result["data"]:
        a = build["attributes"]
        version = related(build, "preReleaseVersion", "preReleaseVersions").get("version", "?")
        external = related(build, "buildBetaDetail", "buildBetaDetails").get("externalBuildState", "-")
        review = related(build, "betaAppReviewSubmission", "betaAppReviewSubmissions").get("betaReviewState", "-")
        print(f"  {version} ({a['version']}) | {a['processingState']} | {external} | {review} | {a['uploadedDate'][:10]}")

    print("\nApp Store versions:")
    versions = client.get(f"/apps/{app}/appStoreVersions")["data"]
    for v in versions:
        print(f"  {v['attributes']['versionString']} | {v['attributes'].get('appStoreState')}")
    if not versions:
        print("  none")

    print("\nTestFlight groups:")
    for group in client.get(f"/apps/{app}/betaGroups")["data"]:
        a = group["attributes"]
        kind = "internal" if a.get("isInternalGroup") else "external"
        link = a.get("publicLink") if a.get("publicLinkEnabled") else "no public link"
        print(f"  {a['name']} | {kind} | {link}")


# ── build numbers ───────────────────────────────────────────────────────────


def highest_build_number(client, app):
    """Across every build, following App Store Connect's pages rather than stopping at 200."""
    highest = 0
    page = builds(client, app, **{"fields[builds]": "version"})
    while True:
        for build in page["data"]:
            try:
                highest = max(highest, int(build["attributes"]["version"]))
            except ValueError:
                pass
        following = page.get("links", {}).get("next")
        if not following:
            return highest
        client._authorise()
        response = client._session.get(following, timeout=60)
        response.raise_for_status()
        page = response.json()


def next_build_number(client, _args):
    app, _ = app_id(client)
    print(highest_build_number(client, app) + 1)


# ── distribute ──────────────────────────────────────────────────────────────


def wait_for_build(client, app, version, number, timeout_minutes):
    """The build, once App Store Connect has finished processing it."""
    deadline = time.time() + timeout_minutes * 60
    while True:
        found = builds(client, app, **{"filter[version]": number,
                                       "filter[preReleaseVersion.version]": version})["data"]
        if found:
            state = found[0]["attributes"]["processingState"]
            print(f"  {version} ({number}): {state}", flush=True)
            if state == "VALID":
                return found[0]
            if state in ("FAILED", "INVALID"):
                sys.exit(f"App Store Connect could not process {version} ({number}): {state}.")
        else:
            print(f"  {version} ({number}): not visible yet", flush=True)
        if time.time() > deadline:
            sys.exit(f"{version} ({number}) was not ready after {timeout_minutes} minutes. "
                     "Run distribute again once it has processed.")
        time.sleep(60)


def set_whats_new(client, build_id, text):
    localizations = client.get(f"/builds/{build_id}/betaBuildLocalizations")["data"]
    existing = next((l for l in localizations if l["attributes"].get("locale") == "en-US"), None)
    if existing:
        client.request("PATCH", f"/betaBuildLocalizations/{existing['id']}", json={"data": {
            "type": "betaBuildLocalizations", "id": existing["id"],
            "attributes": {"whatsNew": text}}})
    else:
        client.request("POST", "/betaBuildLocalizations", json={"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": "en-US", "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})


def external_group(client, app, name):
    """The named external group, and whether it was created just now."""
    for group in client.get(f"/apps/{app}/betaGroups")["data"]:
        if group["attributes"]["name"] == name and not group["attributes"].get("isInternalGroup"):
            return group, False
    # Created without the public link, which Apple can refuse on a group with no approved build;
    # the link is turned on once the build is in the group and submitted.
    print(f"Creating the external TestFlight group '{name}'")
    group = client.request("POST", "/betaGroups", json={"data": {
        "type": "betaGroups",
        "attributes": {"name": name},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
    return group, True


# Where a build has been handed to Apple, or through it. Anything else after a refused submission
# means it is not in review, and the run must not look as though it succeeded.
SUBMITTED = {"WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"}
EXTERNAL_OK = {"WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_APPROVED",
               "READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}


def review_state(client, build_id):
    """(Beta App Review state, external build state) for a build, either possibly None."""
    review = None
    try:
        data = client.get(f"/builds/{build_id}/betaAppReviewSubmission").get("data")
        review = data["attributes"].get("betaReviewState") if data else None
    except ApiError:
        pass
    detail = client.get(f"/builds/{build_id}/buildBetaDetail").get("data") or {}
    return review, detail.get("attributes", {}).get("externalBuildState")


def distribute(client, args):
    app, name = app_id(client)
    print(f"Waiting for {name} {args.version} ({args.build}) to finish processing")
    build = wait_for_build(client, app, args.version, args.build, args.timeout)
    build_id = build["id"]

    if args.whats_new:
        with open(args.whats_new, encoding="utf-8") as f:
            text = f.read().strip()
        if text:
            # App Store Connect caps "What to Test" at 4000 characters.
            set_whats_new(client, build_id, text[:4000])
            print("Set 'What to Test'")

    group, created = external_group(client, app, args.group)
    client.request("POST", f"/betaGroups/{group['id']}/relationships/builds",
                   json={"data": [{"type": "builds", "id": build_id}]})
    print(f"Added to '{args.group}'")

    try:
        client.request("POST", "/betaAppReviewSubmissions", json={"data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        print("Submitted for Beta App Review")
    except ApiError as e:
        # A refusal can mean it is already submitted or approved - fine - or that something is
        # missing, such as the app's TestFlight Test Information, which blocks the first external
        # build. Only the build's own state says which.
        review, external = review_state(client, build_id)
        if review in SUBMITTED or external in EXTERNAL_OK:
            print(f"Already with Apple: review {review}, external testing {external}")
        else:
            sys.exit(f"Not submitted for Beta App Review ({e}). Review state {review}, external state "
                     f"{external}. If this is the first external build, fill in TestFlight -> Test "
                     "Information in App Store Connect, then run the workflow with only_distribute.")

    # A group made just now gets its public link. An existing group is left as it is: if its link
    # is off, someone turned it off.
    if created:
        try:
            client.request("PATCH", f"/betaGroups/{group['id']}", json={"data": {
                "type": "betaGroups", "id": group["id"],
                "attributes": {"publicLinkEnabled": True, "publicLinkLimitEnabled": False}}})
        except ApiError as e:
            print(f"Could not turn on the public link yet (it can be turned on once the build is "
                  f"approved): {e}")

    refreshed = client.get(f"/betaGroups/{group['id']}")["data"]["attributes"]
    if refreshed.get("publicLinkEnabled") and refreshed.get("publicLink"):
        print(f"Public link: {refreshed['publicLink']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    commands.add_parser("next-build-number")
    d = commands.add_parser("distribute")
    d.add_argument("--version", required=True)
    d.add_argument("--build", required=True)
    d.add_argument("--group", default=DEFAULT_GROUP)
    d.add_argument("--whats-new")
    d.add_argument("--timeout", type=int, default=60, help="minutes to wait for processing")
    args = parser.parse_args()

    client = Client()
    {"status": status, "next-build-number": next_build_number, "distribute": distribute}[args.command](client, args)


if __name__ == "__main__":
    main()
