# antioch-wiki

The wiki used by the [Antioch Forever](https://antiochforever.org/) web site, originally written in 2003. It is a derivative of [UseModWiki](http://www.usemod.com/cgi-bin/wiki.pl) with some significant changes:

- It links with [phpBB](https://www.phpbb.com/) forum accounts for user authentication.
- It uses SQLite databases for its page store and for managing user sessions.
- It uses a template system.

It is written for Perl 5 and designed to run in a CGI or mod\_perl environment. It requires the following non-core modules to be installed:

- [Authen::Passphrase::PHPass](https://metacpan.org/pod/Authen::Passphrase::PHPass) (for phpBB 3.0.x) and [Crypt::Argon2](https://metacpan.org/pod/release/LEONT/Crypt-Argon2-0.006/lib/Crypt/Argon2.pm) (for phpBB 3.1.x+)
- [CGI](https://metacpan.org/pod/CGI)
- [DBI](https://metacpan.org/pod/DBI) with [DBD::mysql](https://metacpan.org/pod/DBD::mysql) and [DBD:SQLite](https://metacpan.org/pod/DBD::SQLite)
- [HTML::Template](https://metacpan.org/pod/HTML::Template)
- [Image::Size](https://metacpan.org/pod/Image::Size)
- [Text::Diff](https://metacpan.org/pod/Text::Diff)

MySQL database information must be added to "wiki.pl" for user account authentication to work.

The wiki will automatically create the necessary SQLite database tables the first time it is executed. Users can be elevated to administrators by changing their `level` to 1 in "users.sqlite" (default is 0).

## Acknowledgments

Based on [UseModWiki](http://www.usemod.com/cgi-bin/wiki.pl) by Clifford A. Adams, Sunir Shah, and contributors.

## Authors

- J.C. Fields <jcfields@jcfields.dev>

## License

- [GNU General Public License, version 2](https://opensource.org/licenses/GPL-2.0)
