import Foundation

/// Feed and OPML documents the tests read, including the malformed ones.
public enum SampleFeeds {
    public static let rss2 = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Example News</title>
        <link>https://example.com</link>
        <item>
          <title>Older story</title>
          <link>https://example.com/older</link>
          <description>Something happened.</description>
          <pubDate>Mon, 02 Mar 2026 09:00:00 GMT</pubDate>
        </item>
        <item>
          <title>Newer story</title>
          <link>https://example.com/newer</link>
          <description>Something else happened.</description>
          <pubDate>Tue, 03 Mar 2026 09:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """

    /// One item's date is nonsense. On Windows that used to throw from a property getter and
    /// take the whole feed down; the other two items must still arrive.
    public static let rss2WithBadDate = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Sloppy Dates</title>
        <item><title>Good one</title><link>https://example.com/1</link><pubDate>Mon, 02 Mar 2026 09:00:00 GMT</pubDate></item>
        <item><title>Bad date</title><link>https://example.com/2</link><pubDate>last Tuesday-ish</pubDate></item>
        <item><title>Also good</title><link>https://example.com/3</link><pubDate>Wed, 04 Mar 2026 09:00:00 GMT</pubDate></item>
      </channel>
    </rss>
    """

    /// A podcast: the enclosure comes before the article link, which is the shape that made
    /// Enter open an MP3 instead of the episode page.
    public static let podcast = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>A Podcast</title>
        <item>
          <title>Episode 4</title>
          <enclosure url="https://example.com/episode4.mp3" type="audio/mpeg" length="1234"/>
          <link>https://example.com/episode-4</link>
          <pubDate>Fri, 06 Mar 2026 09:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """

    public static let atom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Atom Example</title>
      <entry>
        <title>An entry</title>
        <link rel="edit" href="https://example.com/edit/1"/>
        <link rel="alternate" href="https://example.com/entry-1"/>
        <summary>A summary.</summary>
        <published>2026-03-02T09:00:00Z</published>
        <updated>2026-03-05T11:30:00Z</updated>
        <author><name>A Writer</name></author>
      </entry>
    </feed>
    """

    public static let rdf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns="http://purl.org/rss/1.0/"
             xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel rdf:about="https://example.com"><title>RDF Example</title></channel>
      <item rdf:about="https://example.com/a">
        <title>An RDF item</title>
        <link>https://example.com/a</link>
        <dc:date>2026-03-02T09:00:00Z</dc:date>
        <dc:creator>Someone</dc:creator>
      </item>
    </rdf:RDF>
    """

    /// Titles carrying the invisible characters that read as blank cells on a braille display.
    public static let braille = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Braille Trouble</title>
        <item><title>\u{200B}\u{00A0}Lions GM\t\tBrad Holmes\u{FEFF}</title><link>https://example.com/l</link></item>
      </channel>
    </rss>
    """

    public static let notAFeed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <catalogue><product>A hat</product></catalogue>
    """

    public static let malformedXML = "<rss><channel><title>Unclosed"

    public static let opml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head><title>Test feeds</title></head>
      <body>
        <outline text="News">
          <outline text="Wires">
            <outline text="Reuters" type="rss" xmlUrl="https://example.com/reuters.xml"/>
            <outline text="AP" type="rss" xmlUrl="https://example.com/ap.xml"/>
          </outline>
          <outline text="Papers">
            <outline text="The Guardian" type="rss" xmlUrl="https://example.com/guardian.xml"/>
          </outline>
        </outline>
        <outline text="A loose feed" type="rss" xmlUrl="https://example.com/loose.xml"/>
      </body>
    </opml>
    """
}
