# Security policy

## Reporting a vulnerability

**Please do not open a public GitHub issue for a security vulnerability.**

Use GitHub's private vulnerability reporting: on the [Security tab](https://github.com/kellylford/rssquick/security) of this repository, choose **Report a vulnerability**. If you cannot use that, send a private message to [@kellylford](https://github.com/kellylford) on GitHub.

Please include:

- What the vulnerability is and what someone could do with it
- Steps to reproduce, or a minimal proof of concept
- The version of RSS Quick you tested against
- Your Windows version

You will get an acknowledgement within a few days. Confirmed reports are fixed and released as quickly as is practical, and you will be credited in the release notes unless you would rather not be.

## Scope

RSS Quick is a local desktop application with no accounts, no server, and no stored credentials. The areas most likely to matter:

- **Feed parsing.** Feed content is fetched over the network from third-party servers and parsed with `System.ServiceModel.Syndication`. Malformed or hostile feed XML reaching the parser is in scope, including XML entity expansion and anything that escapes the parser.
- **Opening articles.** Article links come from feed content and are handed to the default browser. A link that causes something other than a browser navigation is in scope.
- **OPML import.** OPML files are user-supplied XML. Anything a crafted OPML file can do beyond adding feeds to the tree is in scope.
- **The installer.** Anything that lets a non-administrator install to, or write into, a location they should not reach.

Out of scope: the content of third-party feeds themselves, and the behaviour of your browser once an article is open in it.

## Supported versions

The most recent release is supported. RSS Quick is a small project with one maintainer; there are no long-term support branches.
