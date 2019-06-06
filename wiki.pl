#!/usr/bin/perl -T
################################################################################
# Antioch Wiki                                                                 #
#                                                                              #
# Copyright (C) 2003-2013 J.C. Fields (jcfields@jcfields.dev).                 #
#                                                                              #
# Based on UseModWiki, v1.0...                                                 #
#                                                                              #
# Copyright (C) 2000-2003 Clifford A. Adams (caadams@usemod.com).              #
# Copyright (C) 2002-2003 Sunir Shah (sunir@sunir.org).                        #
#                                                                              #
# ...which was based on the GPLed AtisWiki, v0.3.                              #
#                                                                              #
# Copyright (C) 1998 Markus Denker (marcus@ira.uka.de).                        #
#                                                                              #
# ...which was based on the LGPLed CVWiki CVS-patches.                         #
#                                                                              #
# Copyright (C) 1997 Peter Merel.                                              #
#                                                                              #
# ...and the Original WikiWikiWeb (code reused with permission).               #
#                                                                              #
# Copyright (C) 1994-1995 Ward Cunningham (ward@c2.com).                       #
#                                                                              #
# This program is free software; you can redistribute it and/or modify it      #
# under the terms of the GNU General Public License as published by the Free   #
# Software Foundation; either version 2 of the License, or (at your option)    #
# any later version.                                                           #
#                                                                              #
# This program is distributed in the hope that it will be useful, but WITHOUT  #
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or        #
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for     #
# more details.                                                                #
#                                                                              #
# You should have received a copy of the GNU General Public License along with #
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple #
# Place, Suite 330, Boston, MA 02111-1307 USA.                                 #
################################################################################

use strict;
use warnings;

use Authen::Passphrase::PHPass;
use CGI;
use Crypt::Argon2 'argon2id_verify';
use DBI ':sql_types';
use File::Basename;
use HTML::Template;
use Image::Size 'html_imgsize';
use POSIX 'strftime';
use Text::Diff;

################################################################################
# Global variables                                                             #
################################################################################

use vars qw(
	@HeadingNumbers %LinkIndex %SaveNumUrl %SaveUrl

	$FreeLink $FS $Now $PrintSheet $q $SaveNumUrlIndex $SaveUrlIndex $SetCookie
	$StyleSheet $TableMode $TableOfContents $TimeZone $UrlPattern $UserLevel
	$UserName
);

################################################################################
# Configuration                                                                #
################################################################################

use constant {
	# script paths
	BASE_DIR      => dirname(__FILE__),        # for mod_perl
	SCRIPT_NAME   => basename(__FILE__),       # name used in links
	# general options
	SITE_NAME     => 'AntiochWiki',            # name of site
	PREFS_COOKIE  => 'wiki',                   # name of wiki preferences cookie
	LOGIN_COOKIE  => 'session',                # name of login session cookie
	ENCODING      => 'utf-8',                  # character encoding
	RC_DEFAULT    => 30,                       # default days for Recent Changes
	RSS_EMAIL     => '',                       # e-mail address for RSS feed
	TIME_ZONE     => -5,                       # default time zone (UTC offset)
	RECENT_POSTS  => 6,                        # recent forum posts shown
	# data locations
	DATA_DIR      => 'store',                  # main data directory
	PAGE_DB       => 'pages.sqlite',           # page database
	USER_DB       => 'users.sqlite',           # user sessions database
	FILE_INDEX    => 'files.txt',              # list of all files (or '')
	BAN_LIST      => 'banlist.txt',            # list of banned IPs/hosts
	LOCK_ALL      => 'wikilock.txt',           # wiki lock file
	# file locations
	FILES_DIR     => 'files',                  # files directory
	FILE_INFO     => '',                       # file information script (or '')
	UPLOAD_FORM   => '',                       # upload form (or '')
	FORUM_RSS     => '',                       # forum RSS feed (or '')
	# templates and themes
	THEME_DIR     => 'schemes',                # theme directory
	TEMPLATE_DIR  => 'templates',              # template directory
	STYLE_SHEET   => 'slug',                   # default screen style sheet
	PRINT_SHEET   => 'newmoon',                # default print style sheet
	# special pages (change spaces to _)
	HOME_PAGE     => 'Home',                   # home page
	RECENT_PAGE   => 'Recent_Changes',         # recent changes page
	DISCUSS_PAGE  => 'Chatter',                # discussion page
	FORMAT_PAGE   => 'Text_Formatting_Rules',  # text formatting rules page
	# forum DBMS settings
	DB_DRIVER     => 'mysql',                  # DBI driver (e.g., 'mysql')
	DB_DATABASE   => '',                       # database name
	DB_HOST       => 'localhost',              # host name of database server
	DB_PORT       => 3306,                     # port of database server
	DB_USERNAME   => '',                       # DBMS user name
	DB_PASSWORD   => '',                       # DBMS password
	DB_PREFIX     => 'phpbb_',                 # table prefix (e.g., 'phpbb_')
	# other options
	HTML_TAGS     => 1,              # 1=allow HTML tags,    0=only minimal tags
	HTML_LINKS    => 1,              # 1=allow A HREF links, 0=no raw HTML links
	FORCE_UPPER   => 0,              # 1=force upper case,   0=do not force case
	INDENT_LIMIT  => 20,             # maximum depth of nested lists
	MAX_POST      => 210             # maximum 210K POSTs (about 200K for pages)
};

# IDs of pages to appear in menu bar
use constant MENU_ITEMS => qw(Home Recent_Changes);

# days for links on Recent Changes
use constant RC_DAYS => qw(30 90 365);

# HTML tag lists, enabled if HTML_TAGS is set
# tags that must be in <tag>...</tag> pairs:
use constant HTML_PAIRS => qw(
	b big blockquote caption center cite code dd del div dl dt em font h3 h4 h5
	h6 i ins li ol p s small span strike strong sub sup table td th tr tt u ul
);
# single tags (that do not require a closing </tag>):
use constant HTML_SINGLE => qw(br img);

# block-level elements (for clean-up subroutine)
use constant HTML_BLOCK => qw(
	address blockquote center div dl fieldset form h1 h2 h3 h4 h5 h6 hr noscript
	ol p pre table ul
);

# time zones
use constant TIME_ZONES => (
	-12 => 'UTC−12—Baker Island Time',
	-11 => 'UTC−11—Niue Time, Samoa Standard Time',
	-10 => 'UTC−10—Hawaii-Aleutian Standard Time, Cook Island Time',
	-9.5 => 'UTC−9:30—Marquesas Islands Time',
	-9 => 'UTC−9—Alaska Standard Time, Gambier Island Time',
	-8 => 'UTC−8—Pacific Standard Time',
	-7 => 'UTC−7—Mountain Standard Time',
	-6 => 'UTC−6—Central Standard Time',
	-5 => 'UTC−5—Eastern Standard Time',
	-4.5 => 'UTC−4:30—Venezuelan Standard Time',
	-4 => 'UTC−4—Atlantic Standard Time',
	-3.5 => 'UTC−3:30—Newfoundland Standard Time',
	-3 => 'UTC−3—Amazon Standard Time, Central Greenland Time',
	-2 => 'UTC−2—South Georgia and South Sandwich Islands Time',
	-1 => 'UTC−1—Azores Standard Time, Cape Verde Time, Eastern Greenland Time',
	0 => 'UTC—Western European Time, Greenwich Mean Time',
	1 => 'UTC+1—Central European Time, West African Time',
	2 => 'UTC+2—Eastern European Time, Central African Time',
	3 => 'UTC+3—Moscow Standard Time, Eastern African Time',
	3.5 => 'UTC+3:30—Iran Standard Time',
	4 => 'UTC+4—Gulf Standard Time, Samara Standard Time',
	4.5 => 'UTC+4:30—Afghanistan Time',
	5 => 'UTC+5—Pakistan Standard Time, Yekaterinburg Standard Time',
	5.5 => 'UTC+5:30—Indian Standard Time, Sri Lanka Time',
	5.75 => 'UTC+5:45—Nepal Time',
	6 => 'UTC+6—Bangladesh Time, Bhutan Time, Novosibirsk Standard Time',
	6.5 => 'UTC+6:30—Cocos Islands Time, Myanmar Time',
	7 => 'UTC+7—Indochina Time, Krasnoyarsk Standard Time',
	8 => 'UTC+8—Chinese Standard Time, Australian Western Standard Time',
	8.75 => 'UTC+8:45—Southeastern Western Australia Standard Time',
	9 => 'UTC+9—Japan Standard Time, Korea Standard Time, Chita Standard Time',
	9.5 => 'UTC+9:30—Australian Central Standard Time',
	10 => 'UTC+10—Australian Eastern Standard Time, Vladivostok Standard Time',
	10.5 => 'UTC+10:30—Lord Howe Standard Time',
	11 => 'UTC+11—Solomon Island Time, Magadan Standard Time',
	11.5 => 'UTC+11:30—Norfolk Island Time',
	12 => 'UTC+12—New Zealand Time, Fiji Time, Kamchatka Standard Time',
	12.75 => 'UTC+12:45—Chatham Islands Time',
	13 => 'UTC+13—Tonga Time, Phoenix Islands Time',
	14 => 'UTC+14—Line Island Time'
);

################################################################################
# Initialization functions                                                     #
################################################################################

sub do_wiki_request {
	$FS = "\xff";
	$FreeLink = "([-,.()' _0-9A-Za-z\x80-\xff]+)";

	my $url_protocols = 'http|https|ftp|news|nntp|mailto';
	my $url_chars = '[-a-zA-Z0-9/@=+$_~*.,;:?!\'"()&#%]'; # RFC 2396
	my $end_chars = '[-a-zA-Z0-9/@=+$_~*]'; # no punctuation at end of URL

	$UrlPattern = "((?:$url_protocols):$url_chars+$end_chars)";

	init_request()
		or return 0;

	do_other_request() if (!do_browse_request());

	return 1;
}

sub init_request {
	if (-d join('/', BASE_DIR, TEMPLATE_DIR)) {
		$ENV{'HTML_TEMPLATE_ROOT'} = join('/', BASE_DIR, TEMPLATE_DIR);
	} else {
		die 'Could not open template directory: ', TEMPLATE_DIR;
	}

	$CGI::POST_MAX = MAX_POST * 1024;
	$CGI::DISABLE_UPLOADS = 1; # no uploads

	$q = CGI->new();
	$q->charset(ENCODING);

	# resets in case script is persistent
	$Now = time;

	# creates and initializes data directory if it does not exist
	create_data_dir();

	$SetCookie = ();
	($StyleSheet, $PrintSheet, $TimeZone) = read_prefs();
	($UserName, $UserLevel) = is_user_logged_in();

	$TimeZone *= 3600; # converts time zone offset from hours to seconds

	return 1;
}

sub create_data_dir {
	if (!-d join('/', BASE_DIR, DATA_DIR)) {
		mkdir join('/', BASE_DIR, DATA_DIR), 0775
			or die 'Could not create data directory: ', DATA_DIR;
	}

	if (!-f join('/', BASE_DIR, DATA_DIR, PAGE_DB)) {
		my $page_link = connect_to_page_db()
			or die 'Could not connect to page database: ', PAGE_DB;
		$page_link->do('
			CREATE TABLE pagemeta
			(page TEXT NOT NULL,
			 entry TEXT NOT NULL,
			 value TEXT NOT NULL,
			 PRIMARY KEY (page, entry))
		');
		$page_link->do('
			CREATE TABLE pagetext
			(page TEXT NOT NULL,
			 timestamp INTEGER NOT NULL,
			 revision INTEGER NOT NULL,
			 text TEXT NOT NULL,
			 editor TEXT,
			 host TEXT,
			 ip TEXT,
			 summary TEXT,
			 type INTEGER,
			 newauthor INTEGER,
			 PRIMARY KEY (page, timestamp))
		');
		$page_link->disconnect();
	}

	if (!-f join('/', BASE_DIR, DATA_DIR, USER_DB)) {
		my $user_link = connect_to_user_db()
			or die 'Could not connect to user database: ', USER_DB;
		$user_link->do('
			CREATE TABLE users
			(username TEXT NOT NULL,
			 level INTEGER NOT NULL,
			 sessionid TEXT NOT NULL,
			 timestamp INTEGER NOT NULL,
			 PRIMARY KEY (username),
			 UNIQUE (username, sessionid))
		');
		$user_link->disconnect();
	}

	return 1;
}

sub read_prefs {
	my ($style_sheet, $print_sheet, $time_zone);
	my $cookie = $q->cookie(PREFS_COOKIE);

	if ($cookie) {
		($style_sheet, $print_sheet, $time_zone) = split '&', $cookie;
	}

	$style_sheet ||= STYLE_SHEET;
	$print_sheet ||= PRINT_SHEET;
	$time_zone ||= TIME_ZONE;

	return ($style_sheet, $print_sheet, int $time_zone);
}

sub get_param {
	my ($name, $default) = @_;

	my $result = $q->param($name);
	$result = $default if (!defined $result);

	return $result;
}

################################################################################
# Page metadata functions                                                      #
################################################################################

sub connect_to_page_db {
	return DBI->connect('DBI:SQLite:' . join('/', BASE_DIR, DATA_DIR, PAGE_DB));
}

sub read_page_meta {
	my ($page, $entry) = @_;

	my $page_link = connect_to_page_db()
		or return '';

	my $query = $page_link->prepare('
		SELECT value FROM pagemeta WHERE page = ? AND entry = ?
	');
	$query->execute($page, $entry);

	my ($value) = $query->fetchrow_array();
	$query->finish();
	$page_link->disconnect();

	return $value;
}

sub add_page_meta {
	my ($page, $entry, $value) = @_;

	# no empty fields
	return 0 if (!$entry || !$value);
	# 64-byte limit for entry names, 32-KB limit for values
	return 0 if (length $entry > 64 || length $value > 32 * 1024);

	my $page_link = connect_to_page_db()
		or return 0;

	my $query = $page_link->prepare('
		SELECT COUNT(*) FROM pagemeta WHERE page = ? AND entry = ?
	');
	$query->execute($page, $entry);

	# overwrites value if entry already exists
	if ($query->fetchrow_array()) {
		$query = $page_link->prepare('
			UPDATE pagemeta SET value = ? WHERE page = ? AND entry = ?
		');
		$query->execute($value, $page, $entry);
	} else {
		$query = $page_link->prepare('
			INSERT INTO pagemeta (page, entry, value) VALUES (?, ?, ?)
		');
		$query->execute($page, $entry, $value);
	}

	$page_link->disconnect();

	return 1;
}

sub delete_page_meta {
	my ($page, $entry) = @_;

	my $page_link = connect_to_page_db()
		or return 0;

	my $query = $page_link->prepare('
		DELETE FROM pagemeta WHERE page = ? AND entry = ?
	');
	$query->execute($page, $entry);
	$page_link->disconnect();

	return 1;
}

sub move_all_page_meta {
	my ($old, $new) = @_;

	my $page_link = connect_to_page_db()
		or return 0;

	my $query = $page_link->prepare('
		UPDATE pagemeta SET page = ? WHERE page = ?
	');
	$query->execute($new, $old);
	$page_link->disconnect();

	return 1;
}

sub delete_all_page_meta {
	my ($page) = @_;

	my $page_link = connect_to_page_db()
		or return 0;

	my $query = $page_link->prepare('DELETE FROM pagemeta WHERE page = ?');
	$query->execute($page);
	$page_link->disconnect();

	return 1;
}

sub page_exists {
	my ($id) = @_;

	return read_page_meta($id, 'revision');
}

sub is_valid_id {
	my ($id) = @_;
	my $error = '';

	$error = 'No page name given.' if (!$id);
	$error = "Page name “$id” is too long." if (length $id > 120);
	$error = "Page name “$id” may not contain spaces." if ($id =~ / /);

	$id = string_page_id($id);

	$error = "Invalid page name “$id” (“/” not allowed)." if ($id =~ m|/|);
	$error = "Invalid page name “$id.”" if ($id !~ /^$FreeLink$/);

	return $error;
}

sub is_valid_id_or_error {
	my ($id) = @_;
	my $error;

	$error = is_valid_id($id);

	if ($error) {
		report_error($error);
		return 0;
	}

	return 1;
}

sub is_page_locked {
	my ($id) = @_;

	return read_page_meta($id, 'locked');
}

sub is_wiki_locked {
	return -f join('/', BASE_DIR, DATA_DIR, LOCK_ALL);
}

################################################################################
# User functions                                                               #
################################################################################

sub connect_to_user_db {
	return DBI->connect('DBI:SQLite:' . join('/', BASE_DIR, DATA_DIR, USER_DB));
}

sub is_user_logged_in {
	my ($user_name, $session_id) = read_login();
	return ('', 0) if (!$user_name || !$session_id);

	my $user_link = connect_to_user_db()
		or return ('', 0);
	my $query = $user_link->prepare('
		SELECT username, level, sessionid FROM users
		WHERE username = ? AND sessionid = ?
	');
	$query->execute($user_name, $session_id);

	my ($db_user_name, $db_level, $db_session_id) = $query->fetchrow_array();
	$query->finish();
	$user_link->disconnect();

	return ('', 0) if (!is_equal($user_name, $db_user_name));
	return ('', 0) if (!is_equal($session_id, $db_session_id));

	return ($db_user_name, $db_level);
}

sub is_equal {
	my ($a, $b) = @_;

	return 0 if (length $a != length $b);

	my $result = 0;

	# constant-time string comparison
	for my $i (0 .. (length $a) - 1) {
		$result |= ord substr($a, $i, 1) ^ ord substr($b, $i, 1);
	}

	return $result == 0;
}

sub create_session {
	my ($user_name) = @_;

	my $timestamp = time;
	my $session_id = 0;

	my $user_link = connect_to_user_db()
		or return 0;
	my $query = $user_link->prepare('
		SELECT sessionid FROM users WHERE username = ?
	');
	$query->execute($user_name);

	if (($session_id) = $query->fetchrow_array()) { # looks for existing session
		$query = $user_link->prepare('
			UPDATE users SET timestamp = ? WHERE username = ?
		');
		$query->execute($timestamp, $user_name);
	} else { # creates new session if none already exists
		$session_id = int rand * $timestamp * 2**32;

		$query = $user_link->prepare('
			INSERT INTO users (username, level, sessionid, timestamp)
			VALUES (?, ?, ?, ?)
		');
		$query->bind_param(1, $user_name, SQL_VARCHAR);
		$query->bind_param(2, 0, SQL_INTEGER);
		$query->bind_param(3, $session_id, SQL_VARCHAR);
		$query->bind_param(4, $timestamp, SQL_INTEGER);
		$query->execute();
	}

	$user_link->disconnect();
	return $session_id;
}

sub read_login {
	my $cookie = $q->cookie(LOGIN_COOKIE);

	return ('', '') if (!$cookie);

	return split ',', $cookie;
}

sub can_user_edit {
	my ($id) = @_;

	return 1 if (is_user_admin());     # admins can always edit
	return 0 if (is_wiki_locked());    # global lock set
	return 0 if (is_page_locked($id)); # page locked (only admins can edit)
	return 0 if (is_user_banned());    # IP is banned

	return $UserName; # returns user name if user is logged in
}

sub is_user_banned {
	open my $handle, '<', join('/', BASE_DIR, DATA_DIR, BAN_LIST)
		or return 0;

	my $ban_list = <$handle>;
	$ban_list =~ s/\r\n?/\n/gs;
	close $handle;

	my $ip = $ENV{'REMOTE_ADDR'};
	my $host = get_remote_host($ip);

	for (split /\n/, $ban_list) {
		next if (/^\s*$/ || /^#/); # skips empty, spaces, or comments

		return 1 if ($ip =~ /$_/i);
		return 1 if ($host =~ /$_/i);
	}

	return 0;
}

sub is_user_admin {
	return $UserLevel > 0;
}

sub is_user_admin_or_error {
	return 1 if (is_user_admin());

	report_error('Only administrators can perform this operation.');
	return 0;
}

sub get_remote_host {
	return $ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'};
}

################################################################################
# Forum functions                                                              #
################################################################################

sub connect_to_forum_db {
	my $forum_link = DBI->connect(
		'DBI:' . join(':', DB_DRIVER, DB_DATABASE, DB_HOST, DB_PORT),
		DB_USERNAME,
		DB_PASSWORD
	) or return 0;

	$forum_link->do('SET character_set_client = utf8');
	$forum_link->do('SET character_set_connection = utf8');
	$forum_link->do('SET character_set_results = utf8');

	return $forum_link;
}

sub do_forum_login {
	my ($user_name, $password) = @_;

	return ('', 'No user name provided.') if (!$user_name);
	return ('', 'No password provided.') if (!$password);

	my $forum_link = connect_to_forum_db()
		or return ('', 'Could not connect to forum database.');

	my $prefix = DB_PREFIX;
	my $query = $forum_link->prepare("
		SELECT user_password, user_posts, user_type, username
		FROM ${prefix}users WHERE username = ? LIMIT ?
	");
	$query->execute($user_name, 1);

	my $row = $query->fetchrow_hashref();
	$query->finish();

	if (!$row->{'username'}) {
		return ('', 'Invalid user name.');
	}

	if ($row->{'user_type'} == 1 || $row->{'user_type'} == 2) {
		return ('', 'User not activated.');
	}

	if ($row->{'user_posts'} == 0) {
		return ('', 'User has no posts.');
	}

	if (length $password > 4 * 1024) {
		return ('', 'Password too long.');
	}

	my $password_hash = $row->{'user_password'};

	if ($password_hash =~ /^\$H\$\d/) { # 3.0.x
		# changes from $H$ (used by phpBB) to $P$
		$password_hash =~ s/^\$H\$(\d)/\$P\$$1/;

		my $ppr = Authen::Passphrase::PHPass->from_crypt($password_hash);

		if (!$ppr->match($password)) {
			return ('', 'Invalid password.');
		}
	} else { # 3.1.x+
		if (!argon2id_verify($password_hash, $password)) {
			return ('', 'Invalid password.');
		}
	}

	$forum_link->disconnect();

	return ($user_name, '');
}

sub do_recent_forum_posts {
	my $forum_link = connect_to_forum_db()
		or return error_msg('Could not connect to forum database.');

	my $prefix = DB_PREFIX;
	my $query = $forum_link->prepare("
		SELECT ${prefix}forums.forum_name, ${prefix}posts.post_id,
			${prefix}posts.post_time, ${prefix}topics.forum_id,
			${prefix}topics.topic_id, ${prefix}topics.topic_posts_approved,
			${prefix}topics.topic_title, ${prefix}topics.topic_views,
			${prefix}users.username
		FROM ${prefix}forums, ${prefix}posts, ${prefix}topics, ${prefix}users
		WHERE ${prefix}forums.forum_id = ${prefix}topics.forum_id
			AND ${prefix}posts.post_id = ${prefix}topics.topic_last_post_id
			AND ${prefix}topics.topic_moved_id = 0
			AND ${prefix}posts.poster_id = ${prefix}users.user_id
		ORDER BY ${prefix}posts.post_time DESC LIMIT ?
	");
	$query->execute(RECENT_POSTS);

	my @posts = ();

	while (my $row = $query->fetchrow_hashref()) {
		my ($date, $views);

		# uses day of the week if post is less than a week old
		if ((time - $row->{'post_time'}) < (60 * 60 * 24 * 7)) {
			$date = calc_day($row->{'post_time'});
		} else {
			$date = calc_short_date($row->{'post_time'});
		}

		if ($row->{'topic_views'} > 9999) {
			$views = '<em>a lot</em>';
		} else {
			$views = $row->{'topic_views'};
		}

		push @posts, {
			date          => $date,
			time          => calc_time($row->{'post_time'}),
			forum_name    => $row->{'forum_name'},
			post_id       => $row->{'post_id'},
			forum_id      => $row->{'forum_id'},
			topic_id      => $row->{'topic_id'},
			topic_replies => $row->{'topic_posts_approved'} - 1,
			topic_title   => $row->{'topic_title'},
			topic_views   => $views,
			username      => get_page_or_edit_link($row->{'username'})
		};
	}

	$forum_link->disconnect();

	my $template = HTML::Template->new_file('recentposts.tmpl');
	$template->param(posts => \@posts);

	return $template->output();
}

################################################################################
# Page text database functions                                                 #
################################################################################

sub open_page {
	my ($id, $rev) = @_;

	my $page_link = connect_to_page_db()
		or return ();
	my $query;

	if ($rev) { # gets most recent revision unless specified
		$rev = int $rev;

		$query = $page_link->prepare('
			SELECT text, timestamp, revision, editor, host, ip, summary, type,
				newauthor
			FROM pagetext WHERE page = ? AND revision = ?
			ORDER BY timestamp DESC LIMIT 1
		');
		$query->bind_param(1, $id, SQL_VARCHAR);
		$query->bind_param(2, $rev, SQL_INTEGER);
		$query->execute();
	} else {
		$query = $page_link->prepare('
			SELECT text, timestamp, revision, editor, host, ip, summary, type,
				newauthor
			FROM pagetext WHERE page = ? ORDER BY timestamp DESC LIMIT 1
		');
		$query->execute($id);
	}

	my $row = $query->fetchrow_hashref();
	$query->finish();
	$page_link->disconnect();

	return (
		text      => $row->{'text'},
		timestamp => $row->{'timestamp'},
		revision  => $row->{'revision'},
		editor    => $row->{'editor'},
		host      => $row->{'host'},
		ip        => $row->{'ip'},
		summary   => $row->{'summary'},
		type      => $row->{'type'},
		newauthor => $row->{'newauthor'}
	);
}

sub save_page {
	my ($page, $text, $editor, $summary, $type, $hidden, $new_author) = @_;

	my $ip = $ENV{'REMOTE_ADDR'};
	my $revision = read_page_meta($page, 'revision');
	$revision++ if (!$hidden);
	my $timestamp = $Now;

	add_page_meta($page, 'revision', $revision);
	add_page_meta($page, 'timecreate', $timestamp) if (!$revision); # new page
	add_page_meta($page, 'timestamp', $timestamp);

	# converts Windows line breaks
	$text =~ s/\r\n?/\n/gs;
	# adds a newline to the end of the string (if it does not have one)
	$text .= "\n" if ($text !~ /\n$/);

	my $page_link = connect_to_page_db()
		or return 0;
	my $query;

	if ($hidden) {
		$query = $page_link->prepare('
			UPDATE pagetext SET text = ? WHERE page = ? AND revision = ?
		');
		$query->bind_param(1, $text, SQL_VARCHAR);
		$query->bind_param(2, $page, SQL_VARCHAR);
		$query->bind_param(3, $revision, SQL_INTEGER);
	} else {
		$query = $page_link->prepare('
			INSERT INTO pagetext (page, timestamp, revision, text, editor, host,
				ip, summary, type, newauthor)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		');
		$query->bind_param(1, $page, SQL_VARCHAR);
		$query->bind_param(2, $timestamp, SQL_INTEGER);
		$query->bind_param(3, $revision, SQL_INTEGER);
		$query->bind_param(4, $text, SQL_VARCHAR);
		$query->bind_param(5, $editor, SQL_VARCHAR);
		$query->bind_param(6, get_remote_host($ip), SQL_VARCHAR);
		$query->bind_param(7, $ip, SQL_VARCHAR);
		$query->bind_param(8, $summary, SQL_VARCHAR);
		$query->bind_param(9, $type, SQL_INTEGER);
		$query->bind_param(10, $new_author, SQL_INTEGER);
	}

	$query->execute();
	$page_link->disconnect();

	return 1;
}

sub rename_page {
	my ($old, $new, $do_text) = @_;

	$old = string_page_id($old);
	$new = free_to_normal($new);

	return "“$old” is not a valid name." if (is_valid_id($old));
	return "“$new” is not a valid name." if (is_valid_id($new));

	my $page_link = connect_to_page_db()
		or return '';

	# fails if old page does not exist
	my $query = $page_link->prepare('
		SELECT COUNT(*) FROM pagemeta WHERE page = ?
	');
	$query->execute($old);

	if (!$query->fetchrow_array()) {
		$query->finish();
		return "“$old” does not exist.";
	}

	# fails if new page already exists
	$query = $page_link->prepare('
		SELECT COUNT(*) FROM pagemeta WHERE page = ?
	');
	$query->execute($new);

	if ($query->fetchrow_array()) {
		$query->finish();
		return "“$new” already exists.";
	}

	move_all_page_meta($old, $new);

	$query = $page_link->prepare('UPDATE pagetext SET page = ? WHERE page = ?');
	$query->execute($new, $old);
	$page_link->disconnect();

	if ($do_text) {
		build_link_index_page($new); # keeps index up-to-date
		rename_text_links($old, $new);
	}

	return '';
}

sub delete_page {
	my ($page) = @_;

	$page = string_page_id($page);
	$page =~ s/\[+//;
	$page =~ s/\]+//;

	return 0 if (is_valid_id($page));

	delete_all_page_meta($page);

	my $page_link = connect_to_page_db()
		or return 0;
	my $query = $page_link->prepare('DELETE FROM pagetext WHERE page = ?');
	$query->execute($page);
	$page_link->disconnect();

	return 1;
}

################################################################################
# Page browsing code                                                           #
################################################################################

sub do_browse_request {
	if (!$q->param) { # no parameter
		if (!page_exists(HOME_PAGE)) {
			no_page_error(HOME_PAGE);
			return 1;
		}

		browse_page(HOME_PAGE) if (is_valid_id_or_error(HOME_PAGE));
		return 1;
	}

	my $keywords = get_param('keywords', ''); # script?PageName

	if ($keywords) {
		if (!page_exists($keywords)) {
			no_page_error($keywords);
			return 1;
		}

		browse_page($keywords) if (is_valid_id_or_error($keywords));
		return 1;
	}

	my $action = lc get_param('action', '');
	my $id = get_param('id', '');

	if ($action eq 'browse') {
		if (!page_exists($id)) {
			no_page_error($id);
			return 1;
		}

		browse_page($id) if (is_valid_id_or_error($id));
		return 1;
	} elsif ($action eq 'history') {
		do_history($id) if (is_valid_id_or_error($id));
		return 1;
	} elsif ($action eq 'random') {
		do_random();
		return 1;
	} elsif ($action eq 'rc') {
		browse_page(RECENT_PAGE);
		return 1;
	}

	return 0;
}

sub browse_page {
	my ($id) = @_;
	my $html = '';

	my $revision = get_param('revision', 0);
	my %page = open_page($id, $revision);

	if (!%page) {
		report_error('Could not load page.');
		return 0;
	}

	my $text = $page{'text'} || '';

	# raw mode (untreated wiki text)
	if (get_param('raw', 0)) {
		print get_http_header('text/plain'), $text;
		return 1;
	}

	# handles single-level redirect
	my $old_id = get_param('oldid', '');

	if (!$old_id && substr($text, 0, 10) eq '#REDIRECT ') {
		$old_id = $id;

		if ($text =~ /\#REDIRECT\s+\[\[.+\]\]/) {
			($id) = ($text =~ /\#REDIRECT\s+\[\[(.+)\]\]/);
			$id = free_to_normal($id);
		} else {
			($id) = ($text =~ /\#REDIRECT\s+(\S+)/);
		}

		if (!is_valid_id($id)) {
			return rebrowse_page($id, $old_id);
		} else { # not a valid target, continues as normal page
			$id = $old_id;
			$old_id = '';
		}
	}

	if (get_param('diff', 0)) {
		$html = get_diff($id, get_param('diffrevision'), $revision);
	} else {
		$html = wiki_to_html($text);
	}

	my $template = HTML::Template->new_file('page.tmpl');
	$template->param(
		revision        => $revision,
		revision_exists => $revision eq $page{'revision'},
		page            => $html
	);

	print get_header(string_page_name($id), $id, $old_id);
	print $template->output();
	print get_footer($id, $page{'timestamp'}, $page{'editor'}, $page{'host'});

	return 1;
}

sub rebrowse_page {
	my ($new_id, $old_id) = @_;

	if ($old_id) { # target of #REDIRECT (loop-breaking)
		print get_redirect_page("action=browse&id=$new_id&oldid=$old_id");
	} else {
		print get_redirect_page($new_id);
	}

	return 1;
}

sub get_redirect_page {
	my ($id) = @_;

	return $q->redirect($q->url() . '?' . $id);
}

sub do_random {
	my $page_link = connect_to_page_db()
		or return 0;
	my $query = $page_link->prepare('
		SELECT DISTINCT page FROM pagemeta ORDER BY RANDOM() LIMIT 1
	');
	$query->execute();

	my ($id) = $query->fetchrow_array();
	$query->finish();
	$page_link->disconnect();

	rebrowse_page($id, '', 0);

	return 1;
}

sub do_history {
	my ($id) = @_;
	my ($new, $old);
	my @versions = ();

	my $page_link = connect_to_page_db()
		or return 0;
	my $query = $page_link->prepare('
		SELECT revision, timestamp, type, summary, editor, host
		FROM pagetext WHERE page = ? ORDER BY revision DESC
	');
	$query->execute($id);

	for (my $i = 0; my $row = $query->fetchrow_hashref(); $i++) {
		my $link;

		$new = $row->{'revision'} if ($i == 0);
		$old = $row->{'revision'} if ($i == 1);

		if ($i == 0) { # current revision
			$link = get_page_link($id, $row->{'revision'});
		} else {
			$link = get_old_page_link('browse', $id, $row->{'revision'});
		}

		push @versions, {
			checked1    => $i == 1,
			checked2    => $i == 0,
			revision    => $row->{'revision'},
			page_link   => $link,
			date_time   => time_to_text($row->{'timestamp'}),
			type        => $row->{'type'},
			summary     => quote_html($row->{'summary'}),
			author_link => get_author_link($row->{'editor'}, $row->{'host'})
		};
	}

	$page_link->disconnect();

	my $template = HTML::Template->new_file('history.tmpl');
	$template->param(
		script_name => SCRIPT_NAME,
		page_id     => $id,
		revisions   => @versions > 1,
		diff        => get_diff($id, $old, $new),
		versions    => \@versions
	);

	print get_header('Page History'), $template->output(), get_footer($id);
	return 1;
}

sub get_diff {
	my ($id, $old, $new) = @_;

	return '' if (!$old);

	# ensures $old is actually older than $new
	($old, $new) = ($new, $old) if ($new < $old); # swaps variables

	my $page_link = connect_to_page_db()
		or return '';
	my $query = $page_link->prepare('
		SELECT text, editor, host, ip, summary
		FROM pagetext WHERE page = ? AND (revision = ? OR revision = ?)
	');
	$query->execute($id, $old, $new);

	my (@new_page, @old_page);

	for (my $i = 0; my @page = $query->fetchrow_array(); $i++) {
		@old_page = @page if ($i == 0);
		@new_page = @page if ($i == 1);
	}

	$page_link->disconnect();

	my @old_lines = split /^/, quote_html($old_page[0]);
	my @new_lines = split /^/, quote_html($new_page[0]);

	my $diff = diff(\@old_lines, \@new_lines, {STYLE => "OldStyle"});
	my @diff = split /^/, $diff;

	for (@diff) {
		next if (!/^([,\d]+)([acd])([,\d]+)/); # skips non-location lines

		my ($old_bottom, $old_top) = split ',', $1;
		my ($new_bottom, $new_top) = split ',', $3;

		$old_top ||= $old_bottom;
		$new_top ||= $new_bottom;

		if ($2 ne 'a') { # lines changed or removed
			for my $i ($old_bottom .. $old_top) {
				$i--;
				chop $old_lines[$i];
				$old_lines[$i] = sprintf(
					qq{<span class="diffchange">%s</span>\n},
					$old_lines[$i]
				);
			}
		}

		if ($2 ne 'd') { # lines changed or added
			for my $i ($new_bottom .. $new_top) {
				$i--;
				chop $new_lines[$i];
				$new_lines[$i] = sprintf(
					qq{<span class="diffchange">%s</span>\n},
					$new_lines[$i]
				);
			}
		}
	}

	my $template = HTML::Template->new_file('diff.tmpl');
	$template->param(
		old_revision => get_old_page_link('browse', $id, $old, "Revision $old"),
		old_author   => get_author_link($old_page[1], $old_page[2]),
		new_revision => get_old_page_link('browse', $id, $new, "Revision $new"),
		new_author   => get_author_link($new_page[1], $new_page[2]),
		summary      => ($old_page[4] || $new_page[4]),
		old_summary  => $old_page[4],
		new_summary  => $new_page[4],
		old_lines    => convert_array(@old_lines),
		new_lines    => convert_array(@new_lines)
	);

	return $template->output();
}

sub do_recent_changes {
	my $period = get_param('days', RC_DEFAULT);
	my $start = $Now + $TimeZone - (60 * 60 * 24 * $period);

	my $page_link = connect_to_page_db()
		or die 'Could not connect to page database: ', PAGE_DB;
	my $query = $page_link->prepare('
		SELECT page, timestamp, revision, type, editor, host, summary
		FROM pagetext WHERE timestamp >= ? ORDER BY timestamp DESC
	');
	$query->bind_param(1, $start, SQL_INTEGER);
	$query->execute();

	my @days = ();
	my @rows = ();

	while (my $row = $query->fetchrow_hashref()) {
		push @days, calc_long_date($row->{'timestamp'});
		push @rows, {
			link        => get_page_link($row->{'page'}),
			time        => calc_time($row->{'timestamp'}),
			type        => $row->{'type'},
			summary     => quote_html($row->{'summary'}),
			author_link => get_author_link($row->{'editor'}) || $row->{'host'}
		};
	}

	my @updates = ();
	my $pos = 0;

	for my $i (0 .. @rows) {
		my $current = $days[$i] || '';
		my $next = $days[$i + 1] || '';

		if ($current ne $next) {
			my @slice = @rows[$pos .. $i];

			push @updates, {
				date => $current,
				rows => \@slice
			};

			$pos = $i + 1;
		}
	}

	my $last_edit = 0;

	if (!@rows) {
		# gets time of most recent edit if none within requested period
		$query = $page_link->prepare('
			SELECT timestamp FROM pagetext ORDER BY timestamp DESC LIMIT 1
		');
		$query->execute();

		($last_edit) = $query->fetchrow_array();
		$query->finish();
	}

	$page_link->disconnect();

	my @filters = map {
		filter => get_action_link(
			"action=rc&days=$_", $_ == 1 ? '1 day' : "$_ days"
		)
	}, RC_DAYS;

	my $template = HTML::Template->new_file('recentchanges.tmpl');
	$template->param(
		period    => $period == 1 ? '1 day' : "$period days",
		filters   => \@filters,
		days      => \@updates,
		recent    => !@rows,
		last_edit => time_to_text($last_edit)
	);

	return $template->output();
}

sub do_rss {
	my $days = get_param('days', RC_DEFAULT);
	my $start = $Now + $TimeZone - (60 * 60 * 24 * $days);

	my $page_link = connect_to_page_db()
		or return 0;
	my $query = $page_link->prepare('
		SELECT page, timestamp, revision, type, editor, host, summary
		FROM pagetext WHERE timestamp >= ? ORDER BY timestamp DESC
	');
	$query->bind_param(1, $start, SQL_INTEGER);
	$query->execute();

	my $url = encode_url($q->url());
	my @posts = ();

	while (my $row = $query->fetchrow_hashref()) {
		my ($author, $summary);

		if ($row->{'summary'}) {
			$summary = quote_html($row->{'summary'});
		} else {
			$summary = '(No summary.)';
		}

		if ($row->{'editor'}) {
			$author = quote_html($row->{'editor'});
		} else {
			$author = quote_html($row->{'host'});
		}

		my $guid = sprintf(
			'%s?action=browse&id=%s&revision=%s',
			$url,
			$row->{'page'},
			$row->{'revision'}
		);

		push @posts, {
			page_name => string_page_name($row->{'page'}),
			type      => $row->{'type'} ? 'Minor' : 'Major',
			link      => $url . '?' . $row->{'page'},
			summary   => $summary,
			email     => RSS_EMAIL,
			author    => $author,
			date      => calc_rss_date($row->{'timestamp'}),
			guid      => quote_html($guid)
		};
	}

	$page_link->disconnect();

	my $template = HTML::Template->new_file('feed.tmpl');
	$template->param(
		site_name => quote_html(SITE_NAME),
		rc_name   => $url . '?' . encode_arg(RECENT_PAGE),
		posts     => \@posts
	);

	print get_http_header('text/xml'), $template->output();
	return 1;
}

################################################################################
# Page editing                                                                 #
################################################################################

sub do_edit {
	my ($id, $conflict, $old_time, $new_text, $preview) = @_;

	$conflict = 0;
	$id = free_to_normal($id);

	# old revision handling
	my $revision = get_param('revision', 0);

	my %page = open_page($id, $revision);
	my $old_text = $page{'text'} || '';
	my $timestamp = $page{'timestamp'} || $Now;

	$old_text = $new_text if ($preview && !$conflict);
	$old_text =~ s/\r\n?/\n/gs; # converts Windows line breaks
	chomp $old_text;

	my $template = HTML::Template->new_file('edit.tmpl');
	$template->param(
		script_name  => SCRIPT_NAME,
		page_id      => $id,
		timestamp    => $timestamp,
		conflict     => $conflict,
		revision     => $revision,
		last_save    => time_to_text($old_time),
		current_time => time_to_text($Now),
		text         => quote_html($old_text),
		new_text     => quote_html($new_text),
		edit         => can_user_edit(),
		summary      => get_param('summary', ''),
		minor_edit   => get_param('minor_edit'),
		hidden_edit  => get_param('hidden_edit'),
		admin        => is_user_admin(),
		page_link    => get_page_link($id),
		format_link  => get_page_link(FORMAT_PAGE),
		preview      => $preview,
		body         => $preview ? wiki_to_html($old_text) : '',
		logged_in    => $UserName,
		banned       => is_user_banned(),
		page_locked  => is_page_locked($id),
		wiki_locked  => is_wiki_locked()
	);

	print get_header('Edit Page'), $template->output(), get_footer($id);
}

sub do_post {
	my $text = get_param('text', '');
	my $id = get_param('title', '');
	my $summary = get_param('summary', '');
	my $old_time = get_param('oldtime', '');
	my $old_conflict = get_param('old_conflict', '');

	my $hidden = 0;
	my $type = 0;

	if (!can_user_edit($id) && !is_user_admin()) {
		report_error('Authorization failed.');
		return 0;
	}

	$summary =~ s/[\r\n\t]/ /g;

	if (length $summary > 300) { # summary too long
		$summary = substr($summary, 0, 300);
	}

	my %page = open_page($id);
	my $ip = $page{'ip'} || '';
	my $old_text = $page{'text'} || '';
	my $page_time = $page{'timestamp'} || 0;
	my $old_revision = $page{'revision'} || 0;

	my $preview = get_param('preview', '');

	if (!$preview && $old_text eq $text) { # no changes
		rebrowse_page($id, '', 1);
		return 0;
	}

	my $new_author = ($ENV{'REMOTE_ADDR'} ne $ip);
	$new_author = 1 if ($old_revision ==0 ); # new page
	$new_author = 0 if (!$new_author); # standard flag form, not empty

	# detects editing conflicts and resubmit edit
	if ($old_revision > 0 && ($new_author && $old_time != $page_time)) {
		if ($old_conflict > 0) { # conflict again
			do_edit($id, 2, $page_time, $text, $preview);
		} else {
			do_edit($id, 1, $page_time, $text, $preview);
		}

		return 0;
	}

	if ($preview) {
		do_edit($id, 0, $page_time, $text, 1);
		return 0;
	}

	if (get_param('minor_edit', '') eq 'on') {
		$type = 1;
	}

	if (get_param('hidden_edit', '') eq 'on') {
		$hidden = 1;
	}

	save_page($id, $text, $UserName, $summary, $type, $hidden, $new_author);
	rebrowse_page($id, '', 1);

	return 1;
}

################################################################################
# Link functions                                                               #
################################################################################

sub get_full_link_list {
	my @found = ();
	my %pages = ();

	my $page = get_param('page', 1);
	my $url = get_param('url', 0);
	my $exists = get_param('exists', 2);
	my $empty = get_param('empty', 0);
	my $search = get_param('search', '');

	$page = 0 if ($url == 2);

	my @page_list = all_pages_list();

	for my $name (@page_list) {
		$pages{$name} = 1;

		my @links = get_page_links($name, $page, $url);
		my @new_links = ();

		for my $link (@links) {
			next if ($exists == 0 && $pages{$link} == 1);
			next if ($exists == 1 && $pages{$link} != 1);
			next if ($search && $link !~ /$search/);

			push @new_links, $link;
		}

		@links = @new_links;
		unshift @links, $name;

		# if only one item, list is empty
		push @found, join(' ', @links) if ($empty || $#links > 0);
	}

	return @found;
}

sub get_page_links {
	my ($name, $page, $url) = @_;

	my %page = open_page($name);
	my $text = $page{'text'} || '';

	$text =~ s!<nowiki>(.|\n)*?\</nowiki>! !ig;
	$text =~ s!<pre>(.|\n)*?\</pre>! !ig;
	$text =~ s!<code>(.|\n)*?\</code>! !ig;

	my @links = ();

	if ($url) {
		$text =~ s/''+/ /g; # quotes can adjacent to URLs
		$text =~ s/$UrlPattern/push(@links, strip_url_punct($1)), ' '/ge;
	} else {
		$text =~ s/$UrlPattern/ /g;
	}

	if ($page) {
		$text =~ s/\[\[$FreeLink\|[^\]]+\]\]
		          /push(@links, free_to_normal($1)), ' '
		          /xge;
		$text =~ s/\[\[$FreeLink\]\]
		          /push(@links, free_to_normal($1)), ' '
		          /xge;
	}

	return @links;
}

sub update_link_list {
	my ($command_list, $do_text) = @_;
	my $results = '';

	build_link_index() if ($do_text);

	for (split /\n/, $command_list) {
		my $error = '';

		s/\s+$//g;
		next if (!/^[=!|]/); # only valid commands

		$results .= "Processing $_…\n";

		if (/^\!(.+)/) {
			if (delete_page($1)) {
				$results .= "“$1” has been successfully deleted.";
			} else {
				$results .= "“$1” could not be deleted.";
			}
		} elsif (/^\=(?:\[\[)?([^]=]+)(?:\]\])?\=(?:\[\[)?([^]=]+)(?:\]\])?/) {
			$error = rename_page($1, $2, $do_text);

			if ($error) {
				$results .= "“$1” could not be renamed to “$2”: $error";
			} else {
				$results .= "“$1” has been successfully renamed to “$2.”";
			}
		} elsif (/^\|(?:\[\[)?([^]|]+)(?:\]\])?\|(?:\[\[)?([^]|]+)(?:\]\])?/) {
			$error = rename_text_links($1, $2);

			if ($error) {
				$results .= "“$1” could not be renamed to “$2”: $error";
			} else {
				$results .= "“$1” has been successfully renamed to “$2.”";
			}
		}
	}

	return $results;
}

sub build_link_index {
	my @page_list = all_pages_list();
	%LinkIndex = ();

	for my $page (@page_list) {
		build_link_index_page($page);
	}
}

sub build_link_index_page {
	my ($page) = @_;

	my @links = get_page_links($page, 1, 0, 0);
	my %seen = ();

	for my $link (@links) {
		if (defined $LinkIndex{$link}) {
			$LinkIndex{$link} .= " $page" if (!$seen{$link});
		} else {
			$LinkIndex{$link} .= " $page";
		}

		$seen{$link} = 1;
	}
}

# given text, returns substituted text
sub substitute_text_links {
	my ($old, $new, $text) = @_;

	%SaveUrl = ();
	$SaveUrlIndex = 0;

	$text =~ s/$FS(\d)/$1/g; # removes separators

	$text =~ s/(<pre>((.|\n)*?)<\/pre>)/store_raw($1)/gie;
	$text =~ s/(<code>((.|\n)*?)<\/code>)/store_raw($1)/gie;
	$text =~ s/(<nowiki>((.|\n)*?)<\/nowiki>)/store_raw($1)/gie;
	$text =~ s/\[\[$FreeLink\|([^\]]+)\]\]/sub_free_link($1, $2, $old, $new)/ge;
	$text =~ s/\[\[$FreeLink\]\]/sub_free_link($1, '', $old, $new)/ge;

	$text =~ s/(\[$UrlPattern\s+([^\]]+?)\])/store_raw($1)/ge;
	$text =~ s/(\[?$UrlPattern\]?)/store_raw($1)/ge;

	1 while $text =~ s/$FS(\d+)$FS/$SaveUrl{$1}/ge; # restores saved text

	return $text;
}

sub sub_free_link {
	my ($link, $name, $old, $new) = @_;

	my $oldlink = $link;
	$link =~ s/^\s+//;
	$link =~ s/\s+$//;

	if ($link eq $old || free_to_normal($old) eq free_to_normal($link)) {
		$link = $new;
	} else {
		$link = $oldlink; # preserves spaces if no match
	}

	$link = "[[$link";
	$link .= "|$name" if ($name);
	$link .= ']]';

	return store_raw($link);
}

sub sub_wiki_link {
	my ($link, $old, $new) = @_;

	if ($link eq $old) {
		$link = $new;
		$link = "[[$link]]";
	}

	return store_raw($link);
}

sub rename_text_links {
	my ($old, $new) = @_;

	$old = string_page_id($old);
	$new = string_page_id($new);
	my $old_canon = free_to_normal($old);

	return "“$old” is not a valid name." if (is_valid_id($old));
	return "“$new” is not a valid name." if (is_valid_id($new));

	$old = string_page_name($old);
	$new = string_page_name($new);

	# the LinkIndex must be built prior to this routine
	return "Page not in link index." if (!defined $LinkIndex{$old_canon});

	my @page_list = split ' ', $LinkIndex{$old_canon};

	my $page_link = connect_to_page_db()
		or return '';

	for my $page (@page_list) {
		my %page = open_page($page);
		my $old_text = $page{'text'};
		my $new_text = substitute_text_links($old, $new, $old_text);

		if ($old_text ne $new_text) {
			my $query = $page_link->prepare('
				UPDATE pagetext SET text = ? WHERE page = ? AND revision = ?
			');
			$query->bind_param(1, $new_text, SQL_VARCHAR);
			$query->bind_param(2, $page, SQL_VARCHAR);
			$query->bind_param(3, $page{'revision'}, SQL_INTEGER);
			$query->execute();
			$query->finish();
		}
	}

	$page_link->disconnect();

	return '';
}

################################################################################
# Mark-up functions                                                            #
################################################################################

sub restore_saved_text {
	my ($text) = @_;

	1 while ($text =~ s/$FS(\d+)$FS/$SaveUrl{$1}/ge); # restores saved text

	return $text;
}

sub wiki_to_html {
	my ($text) = @_;

	$TableMode = 0;
	%SaveUrl = ();
	%SaveNumUrl = ();
	$SaveUrlIndex = 0;
	$SaveNumUrlIndex = 0;
	$TableOfContents = '';

	$text = quote_html($text);
	$text =~ s/\\ *\r?\n/ /g; # joins lines with backslash at end

	$text = multi_line_markup($text);
	$text = wiki_lines_to_html($text); # line-oriented markup

	while (@HeadingNumbers) {
		pop @HeadingNumbers;
	}

	if ($TableOfContents) {
		my $template = HTML::Template->new_file('contents.tmpl');
		$template->param(
			long     => ($TableOfContents =~ tr/\n//) > 20,
			contents => $TableOfContents
		);
		$text =~ s/__TOC__/$template->output()/ge;
	}

	$text = restore_saved_text($text);
	$text = cleanup_markup($text);

	return $text;
}

sub single_line_markup {
	# the quote markup patterns avoid overlapping tags
	# by matching the inner quotes for the strong pattern
	s!('*)'''''(.*?)'''''!$1<b><i>$2</i></b>!g;
	s!('*)'''(.*?)'''!$1<b>$2</b>!g;
	s!''(.*?)''!<i>$1</i>!g;
	s!`(.[^<>]+?)`!<code>$1</code>!g;
	s!//(.[^<>]+?)//!<cite>$1</cite>!g;

	# headings
	s/(^|\n)\s*(\=+)\s*(#)?\s+([^\n]+)\s+\=+/wiki_heading($2, $4, $3)/ge;
	# blockquotes
	s|^&gt;\s*(.*)|<blockquote><p>$1</p></blockquote>|g;

	if ($TableMode) {
		s!\|\|!</td><td>!g;
		s|!!|</th><th>|g;
	}

	my $files = FILES_DIR;

	# links to local file
	s!\[\[File:/?($files/)?([^|\]]+)\|([^\]]+?)\]\]
	 !store_bracket_url("$files/$2", $3)
	 !xge;

	# links to special action
	s!\[\[Special:([^|]+)\|([^\]]+)\]\]
	 !store_bracket_url("?action=$1", $2)
	 !xge;

	# displays local image
	s!\[\[Image:/?($files/)?([^|\]]+)
	  (\|(left|center|right))?
	  (\|([^|\]]+))?\]\]
	 !get_image($2, $4, $6)
	 !xge;

	s/----+/<hr>/g; # four or more hyphens for a horizontal rule
	s/--/—/g; # two hyphens for an em dash

	s/\{\{([^}]+)}}/get_boilerplate($1)/ge;

	return $_;
}

sub multi_line_markup {
	my ($text) = @_;
	local $_ = $text;

	# the <nowiki> tag stores text with no markup (except quoting HTML)
	s!\&lt;nowiki\&gt;((.|\n)*?)\&lt;/nowiki\&gt;!store_raw($1)!gie;

	# the <pre> tag wraps the stored text with the HTML <pre> tag
	s!\&lt;pre\&gt;((.|\n)*?)\&lt;/pre\&gt;!store_pre($1, 'pre')!gie;
	s!\&lt;code\&gt;((.|\n)*?)\&lt;/code\&gt;!store_pre($1, 'code')!gie;
	s!`((.|\n)*?)`!store_pre($1, 'code')!gie;

	if (HTML_TAGS) {
		for my $t (HTML_PAIRS) {
			s!\&lt;$t\&gt;(.*?)\&lt;/$t\&gt;!<$t>$1</$t>!gis;
			s!\&lt;$t(\s[^<>]+?)\&gt;(.*?)\&lt;/$t\&gt;!<$t$1>$2</$t>!gis;
		}

		for my $t (HTML_SINGLE) {
			s!\&lt;$t\&gt;!<$t>!gi;
			s!\&lt;$t(\s[^<>]+?)\&gt;!<$t$1>!gi;
		}
	}

	if (HTML_LINKS) {
		s!\&lt;a(\s[^<>]+?)\&gt;(.*?)\&lt;/a\&gt;!store_href($1, $2)!gise;
	}

	s/\[\[$FreeLink\|([^\]]+)\]\]/store_page_or_edit_link($1, $2)/ge;
	s/\[\[$FreeLink\]\]/store_page_or_edit_link($1, '')/ge;
	s/\[$UrlPattern\s+([^\]]+?)\]/store_bracket_url($1, $2)/ges;

	s/\[$UrlPattern\]/store_bracket_url($1, '', 0)/ge;
	s/\b(?<!\[\[Image:)($UrlPattern)/store_url($2)/ge;

	return $_;
}

sub wiki_lines_to_html {
	my ($text) = @_;

	my @html_stack = ();
	my $html = '<p>';

	for (split /\n/, $text) { # processes lines one-at-a-time
		my $code = '';
		my $depth = 0;

		$TableMode = 0;

		if (s/^(\;+)([^:]+\:?)\:/<dt>$2<dd>/) {
			$code = 'dl';
			$depth = length $1;
		} elsif (s/^(\:+)(.+)$/<dt><dd>/) {
			$code = 'dl';
			$depth = length $1;
		} elsif (s!^(\*+)(.+)$!<li>$2</li>!) {
			$code = 'ul';
			$depth = length $1;
		} elsif (s!^(\#+)(.+)$!<li>$2</li>!) {
			$code = 'ol';
			$depth = length $1;
		} elsif (s/^\|\|(.*)\|\|\s*$/<tr><td>$1<\/td><\/tr>\n/) {
			$code = 'table';
			$TableMode = 1;
			$depth = 1;
		} elsif (s/^!!(.*)!!\s*$/<tr><th>$1<\/th><\/tr>\n/) {
			$code = 'table';
			$TableMode = 1;
			$depth = 1;
		} elsif (/^[ \t].*\S/) {
			$code = 'pre';
			$depth = 1;
		}

		while (@html_stack > $depth) { # closes tags as needed
			$html .= '</' . (pop @html_stack) . '>';
		}

		if ($depth > 0) {
			$depth = INDENT_LIMIT if ($depth > INDENT_LIMIT);

			if (@html_stack) { # non-empty stack
				my $oldcode = pop @html_stack;

				if ($oldcode ne $code) {
					$html .= "</$oldcode>\n<$code>";
				}

				push @html_stack, $code;
			}

			while (@html_stack < $depth) {
				push @html_stack, $code;
				$html .= "<$code>";
			}
		}

		s/^\s*$/\n<p>/; # blank lines become <p> tags

		$html .= single_line_markup($_);
	}

	while (@html_stack > 0) { # clears stack
		$html .= '</' . (pop @html_stack) . '>';
	}

	return $html;
}

sub cleanup_markup {
	my ($text) = @_;
	local $_ = $text;

	# removes paragraph tag if it precedes a block-level element
	s|^<p>(<(\w+)\s*)|fix_block_element($2, $1)|gem;
	# closes open paragraph tags
	s|^(<p>.*)(?<!</p>)$|$1</p>|gm;
	# removes redundant paragraph tags
	s|<p>(<p[^>]+>)|$1|g;
	s|</p></p>|</p>|g;
	s|<p></p>||g;
	# removes successive blockquote tags
	s|</blockquote>\n?<blockquote>|\n|g;

	return $_;
}

sub fix_block_element {
	my ($tag, $restore) = @_;

	return $restore if (grep {m|^/?$tag$|} HTML_BLOCK);
	return '<p>' . $restore;
}

sub get_bracket_url_index {
	my ($id) = @_;

	return $SaveNumUrl{$id} if ($SaveNumUrl{$id} > 0);

	$SaveNumUrlIndex++;
	$SaveNumUrl{$id} = $SaveNumUrlIndex;

	return $SaveNumUrlIndex;
}

sub store_raw {
	my ($html) = @_;

	$SaveUrl{$SaveUrlIndex} = $html;

	my $raw = $FS . $SaveUrlIndex . $FS;
	$SaveUrlIndex++;

	return $raw;
}

sub store_pre {
	my ($html, $tag) = @_;

	return store_raw("<$tag>$html</$tag>");
}

sub store_href {
	my ($anchor, $text) = @_;

	return '<a' . store_raw($anchor) . ">$text</a>";
}

sub store_url {
	my ($name) = @_;

	my ($link, $extra) = url_link($name);
	$extra ||= '';
	$link = store_raw($link) if ($link); # ensures no empty links are stored

	return $link . $extra;
}

sub url_link {
	my ($raw_name) = @_;
	my ($name, $punct) = split_url_punct($raw_name);

	return (qq{<a href="$name">$name</a>}, $punct);
}

sub store_bracket_link {
	my ($name, $text) = @_;

	return store_raw(get_page_link($name, $text));
}

sub store_bracket_anchored_link {
	my ($name, $anchor, $text) = @_;

	return store_raw(get_page_link("$name#$anchor", $text));
}

sub store_bracket_url {
	my ($url, $text) = @_;

	$text = get_bracket_url_index($url) if (!$text);

	my $files = FILES_DIR;
	my $anchor;

	if ($text =~ /^Image:\/?($files\/)?([^|\]]+)
	              (\|(left|center|right))?
	              (\|([^|\]]+))?
	             /x) {
		$anchor = get_image($2, $4, $6, $url);
	} else {
		if ($url =~ /$files\//) {
			$anchor = get_fancy_file_link($url, $text);
		} else {
			$anchor = qq{<a href="$url">$text</a>};
		}
	}

	return store_raw($anchor);
}

sub store_page_or_edit_link {
	my ($page, $name) = @_;

	$page =~ s/^\s+//; # trims extra spaces
	$page =~ s/\s+$//;

	$name =~ s/^\s+//;
	$name =~ s/\s+$//;

	return store_raw(get_page_or_edit_link($page, $name));
}

sub split_url_punct {
	my ($url) = @_;

	return ($url, '') if ($url =~ s/\"\"$//); # deletes double-quote delimiters

	my ($punct) = ($url =~ /([^a-zA-Z0-9\/\x80-\xff]+)$/);
	$url =~ s/([^a-zA-Z0-9\/\xc0-\xff]+)$//;

	return ($url, $punct);
}

sub strip_url_punct {
	my ($url) = @_;
	my $rest;

	($url, $rest) = split_url_punct($url);

	return $url;
}

sub get_boilerplate {
	my ($type) = @_;
	my ($template, $text);

	if ($type eq 'recentchanges') {
		$text = do_recent_changes();
	} elsif ($type eq 'recentforumposts') {
		$text = do_recent_forum_posts();
	} elsif ($type eq 'searchform' || $type eq 'searchfull') {
		$template = HTML::Template->new_file("$type.tmpl");
		$template->param(script_name => SCRIPT_NAME);
		$text = $template->output();
	} elsif ($type eq 'searchgoogle') {
		$template = HTML::Template->new_file("$type.tmpl");
		$template->param(http_host => $ENV{'HTTP_HOST'});
		$text = $template->output();
	} elsif ($type =~ /^filesdir\|([^}]+)$/) {
		$text = sprintf(
			'<a href="%s">%s</a>',
			FILES_DIR, $1
		) if (FILES_DIR);
	} elsif ($type =~ /^forumrsslink\|([^}]+)$/) {
		$text = get_rss_link(FORUM_RSS, $1) if (FORUM_RSS);
	} elsif ($type =~ /^(nav)
	                   (\:prev=([^|]+)\|([^:]+))?
	                   (\:next=([^|]+)\|([^:]+))?$
	                  /x) {
		$template = HTML::Template->new_file("$1.tmpl");
		$template->param(
			prev      => $2 || 0,
			next      => $5 || 0,
			prev_link => get_page_or_edit_link($3, $4),
			next_link => get_page_or_edit_link($6, $7)
		);
		$text = $template->output();
	} elsif ($type =~ /^(post):([^}]+)\|([^}]+)$/) {
		$template = HTML::Template->new_file("$1.tmpl");
		$template->param(date => $2, poster => get_page_or_edit_link($3));
		$text = $template->output();
	} elsif ($type =~ /^rsslink\|([^}]+)$/) {
		$text = get_rss_link(
			SCRIPT_NAME . '?action=rss&days=' . get_param('days', RC_DEFAULT),
			$1
		);
	} elsif ($type =~ /^uploadform\|([^}]+)$/) {
		$text = sprintf(
			'<a href="%s">%s</a>',
			UPLOAD_FORM, $1
		) if (UPLOAD_FORM);
	} elsif ($type =~ /^(wrongtitle):([^}]+)$/) {
		$template = HTML::Template->new_file("$1.tmpl");
		$template->param(title => $2);
		$text = $template->output();
	}

	return $text || "{{$type}}";
}

sub get_image {
	my ($path, $align, $alt, $url) = @_;
	my ($size, $src);

	if ($path =~ /$UrlPattern/) { # remote images
		$size = '';
		$src = $path;
	} else { # local files
		$src = join('/', FILES_DIR, $path);
		(my $high_dpi_src = $src) =~ s/(.*)\.(\w+)/$1\@2x.$2/;

		$size = html_imgsize(join('/', BASE_DIR, $src)) || '';

		# uses high-res version if it exists
		$src = $high_dpi_src if (-f join('/', BASE_DIR, $high_dpi_src));
	}

	($alt = $src) =~ s|.*/|| if (!$alt); # sets alt text to file name if empty
	$alt = quote_html($alt);
	$alt =~ s/"/&quot;/g;

	my $html = qq{<img src="$src" $size alt="[$alt]" title="$alt">};
	$html = qq{<a href="$url">$html</a>} if ($url);

	if ($align) {
		if ($align eq 'left') {
			$html = qq{<p class="float l">$html</p>};
		} elsif ($align eq 'center') {
			$html = qq{<p class="float c">$html</p>};
		} elsif ($align eq 'right') {
			$html = qq{<p class="float r">$html</p>};
		}
	}

	return $html;
}

sub wiki_heading {
	my ($depth, $text, $use_number) = @_;

	$depth = length $depth;
	$depth = 3 if ($depth < 3);
	$depth = 6 if ($depth > 6);

	# cooks anchor by canonicalizing $text
	my $anchor = $text;
	$anchor =~ s/\<.*?\>//g;
	$anchor =~ s/\W/_/g;
	$anchor =~ s/__+/_/g;
	$anchor =~ s/^_//;
	$anchor =~ s/_$//;

	# last ditch effort
	$anchor = '_' . join('_', @HeadingNumbers) if (!$anchor);

	$text = wiki_heading_number($depth, $text, $anchor, $use_number);

	return qq{<h$depth id="h${depth}_$anchor">$text</h$depth>};
}

sub wiki_heading_number {
	my ($depth, $text, $anchor, $use_number) = @_;

	return '' if (--$depth <= 1); # does not number h1s or h2s

	while (scalar @HeadingNumbers < $depth - 1) {
		push @HeadingNumbers, 1;
	}

	if (scalar @HeadingNumbers < $depth) {
		push @HeadingNumbers, 0;
		$TableOfContents .= "\n<ul>";
	} else {
		$TableOfContents .= '</li>';
	}

	while (scalar @HeadingNumbers > $depth) {
		pop @HeadingNumbers;
		$TableOfContents .= '</ul></li>';
	}

	$HeadingNumbers[$#HeadingNumbers]++;

	my $number = join('.', @HeadingNumbers) if ($use_number);

	# removes embedded links
	$text = restore_saved_text($text);
	$text =~ s/\<a\s[^\>]*?\>\?\<\/a\>//si; # no such page syntax
	$text =~ s/\<a\s[^\>]*?\>(.*?)\<\/a\>/$1/si;

	$text = "$number. $text" if ($number);

	$TableOfContents .= sprintf(
		qq{\n<li><a href="#h%d_%s">%s</a>},
		$depth + 1,
		$anchor,
		$text
	);

	return $text;
}

################################################################################
# Link functions                                                               #
################################################################################

sub get_action_link {
	my ($action, $text) = @_;

	return sprintf(
		'<a href="%s?%s" rel="nofollow">%s</a>',
		SCRIPT_NAME,
		quote_html($action),
		$text
	);
}

sub get_edit_link {
	my ($id, $name, $no_class) = @_;

	$name = $id if (!$name);

	$id = free_to_normal(encode_arg($id));
	$name = string_page_name($name);

	return sprintf(
		'<a href="%s?%s" rel="nofollow"%s>%s</a>',
		SCRIPT_NAME,
		quote_html("action=edit&id=$id"),
		$no_class ? '' : ' class="edit"',
		$name
	);
}

sub get_page_link {
	my ($id, $name) = @_;

	$name = $id if (!$name);

	$id = free_to_normal(encode_arg($id));
	$name = string_page_name($name);

	return sprintf('<a href="%s?%s">%s</a>', SCRIPT_NAME, $id, $name);
}

sub get_rss_link {
	my ($link, $text) = @_;

	return sprintf(
		'<a href="%s" class="rss">%s</a>',
		quote_html($link),
		$text
	);
}

sub get_author_link {
	my ($name, $host) = @_;

	return $name ? get_page_or_edit_link($name) : $host;
}

sub get_delete_link {
	my ($id, $name) = @_;

	$id = free_to_normal($id);
	$name = string_page_name($name);

	return get_action_link("action=delete&id=$id", $name);
}

sub get_old_page_link {
	my ($kind, $id, $revision, $name) = @_;

	$id = free_to_normal($id);
	$name = $name ? string_page_name($name) : $revision;

	return get_action_link("action=$kind&id=$id&revision=$revision", $name);
}

sub get_page_or_edit_link {
	my ($id, $name) = @_;

	$name = $id if (!$name);
	$name = string_page_name($id) if (!$name);

	$id = free_to_normal($id);

	return get_page_link($id, $name) if (page_exists($id));
	return get_edit_link($id, $name);
}

sub get_history_link {
	my ($id, $text) = @_;

	$id = string_page_id($id);

	return get_action_link("action=history&id=$id", $text);
}

sub get_backlinks_link {
	my ($id, $name) = @_;

	$name = string_page_name($name); # displays with spaces
	$id = string_page_id($id); # searches for URL-escaped spaces

	return get_action_link("action=backlinks&id=$id", $name);
}

sub get_page_lock_link {
	my ($id, $status, $name) = @_;

	$id = free_to_normal($id);

	return get_action_link("action=page_lock&set=$status&id=$id", $name);
}

sub get_file_link {
	my ($path, $file_name) = @_;

	$file_name = $path if (!$file_name);

	my $file_url = encode_arg($path);
	$path = encode_url($path);
	$file_name = quote_html($file_name);

	my $link = qq{<a href="$path">$file_name</a>};

	if (FILE_INFO) {
		$link .= sprintf(' <a href="%s?file=%s">»</a>', FILE_INFO, $file_url);
	}

	return $link;
}

sub get_fancy_file_link {
	my ($path, $file_name) = @_;

	my $html = get_file_link($path, $file_name);
	return $html if (!FILE_INFO || !-f join('/', BASE_DIR, $path));

	my @stat = stat join('/', BASE_DIR, $path);
	my $file_size = $stat[7];

	$html .= ' (';

	if ($file_size > 1024**3) {
		$html .= sprintf('%.1f GB', $file_size / 1024**3);
	} elsif ($file_size > 1024**2) {
		$html .= sprintf('%.2f MB', $file_size / 1024**2);
	} elsif ($file_size > 1024) {
		$html .= sprintf('%.0f KB', $file_size / 1024);
	} elsif ($file_size == 1) {
		$html .= '1 byte';
	} else {
		$html .= "$file_size bytes";
	}

	$html .= ')';
	return $html;
}

################################################################################
# Template functions                                                           #
################################################################################

sub convert_array {
	my @array = map {item => $_}, @_;
	return \@array;
}

sub get_http_header {
	my ($type) = @_;

	if ($SetCookie) {
		my $cookie = $q->cookie(
			%$SetCookie,
			-expires => '+1y'
		);

		return $q->header(
			-cookie => $cookie,
			-type   => $type . '; charset=' . ENCODING
		);
	}

	return $q->header(
		-type => $type . '; charset=' . ENCODING
	);
}

sub get_header {
	my ($page_name, $id, $old_id) = @_;

	$page_name = quote_html($page_name);

	my $title = SITE_NAME . ' • ' . $page_name;
	my $page = quote_html(string_page_name($page_name));
	my $old_page = $old_id ? get_edit_link($old_id) : '';

	my @menu = map {link => get_page_link($_)}, MENU_ITEMS;

	my $template = HTML::Template->new_file('header.tmpl');
	$template->param(
		title       => $page eq HOME_PAGE ? SITE_NAME : $title,
		site_name   => SITE_NAME,
		stylesheet  => quote_html($StyleSheet),
		printsheet  => quote_html($PrintSheet),
		error       => $page eq 'Error',
		page_name   => $page_name,
		script_name => SCRIPT_NAME,
		no_index    => (get_param('action', '') || !page_exists($id)),
		home_page   => $page eq HOME_PAGE,
		redirect    => $old_id,
		old_page    => $old_page,
		menu        => \@menu
	);

	return get_http_header('text/html') . $template->output();
}

sub get_footer {
	my ($id, $timestamp, $editor, $host) = @_;
	my $template;

	if ($id) {
		my $action = get_param('action', '');
		my $rev = get_param('revision', 0);

		$timestamp ||= 0;
		$editor ||= '';
		$host ||= '';

		$template = HTML::Template->new_file('footer.tmpl');
		$template->param(
			script_name   => SCRIPT_NAME,
			revision      => $rev,
			edit          => ($action ne 'edit' && !get_param('preview', '')),
			edit_link     => get_edit_link($id, 'Edit', 1),
			old_edit_link => get_old_page_link('edit', $id, $rev, "Edit #$rev"),
			history       => $action ne 'history',
			history_link  => get_history_link($id, 'History'),
			backlinks     => $action ne 'backlinks',
			backlinks_link=> get_backlinks_link($id, 'Backlinks'),
			locked        => is_page_locked($id),
			lock_admin    => (is_user_admin() && $action ne 'page_lock'),
			lock_link     => get_page_lock_link($id, 1, 'Lock'),
			unlock_link   => get_page_lock_link($id, 0, 'Unlock'),
			unlock_admin  => (is_user_admin() && $action ne 'page_lock'),
			delete        => (is_user_admin() && $action ne 'delete'),
			delete_link   => get_delete_link($id, 'Delete'),
			discuss       => ($id ne 'Chatter'),
			discuss_link  => get_page_link(DISCUSS_PAGE, 'Discuss'),
			goto_bar      => get_goto_bar(),
			edited        => ($timestamp && ($editor || $host)),
			editor        => get_author_link($editor, $host),
			edit_time     => time_to_text($timestamp),
			user_name     => $UserName,
			user_page     => get_page_link($UserName)
		);
	} else {
		$template = HTML::Template->new_file('common.tmpl');
		$template->param(
			script_name => SCRIPT_NAME,
			goto_bar    => get_goto_bar(),
			user_name   => $UserName,
			user_page   => get_page_link($UserName)
		);
	}

	return $template->output();
}

sub get_goto_bar {
	my $template = HTML::Template->new_file('goto.tmpl');
	$template->param(
		prefs_link  => get_action_link('action=prefs', 'Preferences'),
		random_link => get_action_link('action=random', 'Random Page'),
		files_dir   => FILES_DIR,
		upload_form => UPLOAD_FORM
	);

	return $template->output();
}

################################################################################
# Error-reporting functions                                                    #
################################################################################

sub report_error {
	my ($message) = @_;

	print get_header('Error'), error_msg($message), get_footer();
}

sub error_msg {
	my ($message) = @_;

	my $template = HTML::Template->new_file('alert.tmpl');
	$template->param(label => 'Error', message => $message);

	return $template->output();
}

sub no_page_error {
	my ($id) = @_;

	if ($id) {
		my $link = get_edit_link($id);
		report_error("There is currently no page named “$link” on the site.");
	} else {
		report_error('No page specified.');
	}
}

################################################################################
# Special request functions                                                    #
################################################################################

sub do_other_request {
	my $action = get_param('action', '');
	my $id = string_page_id(get_param('id', ''));

	if ($action) {
		$action = lc $action;

		if ($action eq 'edit') {
			do_edit($id, 0, 0, '', 0) if (is_valid_id_or_error($id));
		} elsif ($action eq 'admin') {
			do_admin_panel();
		} elsif ($action eq 'allowed_html') {
			do_allowed_html();
		} elsif ($action eq 'backlinks') {
			do_backlinks($id);
		} elsif ($action eq 'ban_list') {
			do_edit_banlist();
		} elsif ($action eq 'delete') {
			do_delete_page($id);
		} elsif ($action eq 'edit_lock') {
			do_edit_lock();
		} elsif ($action eq 'index') {
			do_index();
		} elsif ($action eq 'link_editor') {
			do_edit_links();
		} elsif ($action eq 'links') {
			do_links();
		} elsif ($action eq 'locked') {
			do_lock_list();
		} elsif ($action eq 'login') {
			do_login();
		} elsif ($action eq 'page_lock') {
			do_page_lock($id);
		} elsif ($action eq 'prefs') {
			do_edit_prefs();
		} elsif ($action eq 'rss') {
			do_rss();
		} elsif ($action eq 'version') {
			do_version();
		} else {
			report_error("Invalid action “$action.”");
		}

		return 1;
	}

	if (get_param('edit_prefs', 0)) {
		do_update_prefs();
		return 1;
	}

	if (get_param('edit_ban', 0)) {
		do_update_banned();
		return 1;
	}

	if (get_param('edit_links', 0)) {
		do_update_links();
		return 1;
	}

	my $search = get_param('search', '');

	if ($search || get_param('do_search', '')) {
		do_search($search);
		return 1;
	}

	# handles posted pages
	if (get_param('oldtime', '')) {
		$id = get_param('title', '');
		do_post() if (is_valid_id_or_error($id));
		return 1;
	}

	report_error('Invalid URL.');
	return 0;
}

sub do_login {
	my $user_name = '';
	my $error = '';

	if ($UserName) {
		$user_name = $UserName;
	} else {
		($user_name, $error) = do_forum_login(
			get_param('username', ''),
			get_param('password', '')
		);

		if ($error) {
			report_error($error);
			return 0;
		} elsif ($user_name) {
			my $session_id = create_session($user_name);

			$SetCookie = {
				-name     => LOGIN_COOKIE,
				-value    => $user_name . ',' . $session_id,
				-secure   => 1,
				-httponly => 1
			};

			$UserName = $user_name;
		}
	}

	my $template = HTML::Template->new_file('login.tmpl');
	$template->param(
		user_name => quote_html($user_name),
		error_msg => $error
	);

	print get_header('User Log-in'), $template->output(), get_footer();
	return 1;
}

sub do_backlinks {
	my ($id) = @_;
	my @results = ();

	push @results, search_pages(sprintf('[[%s|', string_page_name($id)));
	push @results, search_pages(sprintf('[[%s]]', string_page_name($id)));
	@results = sort @results;

	print get_header('Backlinks');
	print_page_list(@results);
	print get_footer($id);
}

sub do_index {
	print get_header('List of All Pages');
	print_page_list(all_pages_list());
	print get_footer();
}

sub do_lock_list {
	print get_header('List of All Pages');
	print_page_list(locked_pages_list());
	print get_footer();
}

sub do_links {
	my %exists = ();

	for my $page (all_pages_list()) {
		$exists{$page} = 1;
	}

	my @lines = get_full_link_list();
	my @list = ();

	for my $line (@lines) {
		my @links = ();
		my $link = '';

		for my $page (split ' ', $line) {
			if ($page =~ /\:/) {
				($link) = url_link($page, 0); # no images
			} else {
				if ($exists{$page}) {
					$link = get_page_link($page);
				} else {
					$link = $page;
					$link .= get_edit_link($page, '?');
				}
			}

			push @links, $link;
		}

		push @list, join(' ', @links);
	}

	my $template = HTML::Template->new_file('links.tmpl');
	$template->param(list => convert_array(@list));

	print get_header('Link List'), $template->output(), get_footer();
}

sub do_search {
	my ($string) = @_;
	my (@files_found, @pages_found);

	if (!$string) { # prints index of all pages if no query
		do_index();
		return 0;
	}

	if (!get_param('hidewiki', 0)) {
		@pages_found = search_pages($string);
	}

	if (FILE_INDEX && !get_param('hidefiles', 0)) {
		@files_found = search_files($string);
	}

	# only one page found
	if (@pages_found == 1 && !@files_found) {
		print get_redirect_page($pages_found[0]);
		return 0;
	}

	# only one file found
	if (FILE_INFO && @files_found == 1 && !@pages_found) {
		print $q->redirect(sprintf(
			'%s?file=%s',
			FILE_INFO,
			encode_url(FILES_DIR . $files_found[0])
		));
		return 0;
	}

	my @page_list = page_list(@pages_found);
	my @file_list = file_list(@files_found);

	my $page_count = @pages_found;
	my $file_count = @files_found;

	# prints results page
	my $template = HTML::Template->new_file('searchresults.tmpl');
	$template->param(
		query       => quote_html($string),
		pages_found => $page_count,
		page_count  => $page_count == 1 ? '1 page' : "$page_count pages",
		page_list   => \@page_list,
		file_index  => FILE_INDEX,
		files_found => $file_count,
		file_count  => $file_count == 1 ? '1 file' : "$file_count files",
		file_list   => \@file_list
	);

	print get_header('Search Results'), $template->output(), get_footer();
	return 1;
}

sub do_version {
	browse_page(string_page_id(SITE_NAME));
}

sub do_edit_prefs {
	my $path = join('/', BASE_DIR, THEME_DIR);

	opendir my $handle, $path
		or die 'Could not open theme directory: ', THEME_DIR;
	my @dirs = grep {m/^[^.]/ && -d "$path/$_"} readdir $handle;
	closedir $handle;

	my %screen = ();
	my %print = ();

	for (@dirs) {
		my %theme = read_theme_metadata($_);

		next if (!%theme);

		$screen{$_} = $theme{'name'} if (-f "$path/$_/screen.css");
		$print{$_} = $theme{'name'} if (-f "$path/$_/print.css");
	}

	my %time_zones = TIME_ZONES;

	my $template = HTML::Template->new_file('prefs.tmpl');
	$template->param(
		script_name => SCRIPT_NAME,
		stylesheet  => get_param('stylesheet', $StyleSheet),
		stylesheets => $q->popup_menu(
			-name    => 'p_stylesheet',
			-id      => 'p_stylesheet',
			-values  => [sort keys %screen],
			-labels  => \%screen,
			-default => get_param('stylesheet', $StyleSheet)
		),
		printsheets => $q->popup_menu(
			-name    => 'p_printsheet',
			-id      => 'p_printsheet',
			-values  => [sort keys %print],
			-labels  => \%print,
			-default => get_param('printsheet', $PrintSheet)
		),
		time_zones  => $q->popup_menu(
			-name    => 'p_timezone',
			-id      => 'p_timezone',
			-values  => [sort {$a <=> $b} keys %time_zones],
			-labels  => \%time_zones,
			-default => get_param('timezone', $TimeZone / 3600)
		)
	);

	print get_header('Preferences'), $template->output(), get_footer();
}

sub do_update_prefs {
	my $style_sheet = get_param('p_stylesheet', '');
	my $print_sheet = get_param('p_printsheet', '');
	my $time_zone = int get_param('p_timezone', 0);

	$SetCookie = {
		-name  => PREFS_COOKIE,
		-value => join('&', $style_sheet, $print_sheet, $time_zone)
	};

	my %screen = read_theme_metadata($style_sheet);
	my %print = read_theme_metadata($print_sheet);

	my %time_zones = TIME_ZONES;

	my $template = HTML::Template->new_file('saveprefs.tmpl');
	$template->param(
		stylesheet => quote_html($screen{'name'}),
		printsheet => quote_html($print{'name'}),
		time_zone  => $time_zones{$time_zone}
	);

	print get_header('Preferences'), $template->output(), get_footer();
}

sub do_admin_panel {
	my @info = (
		get_action_link('action=version', 'About This Wiki'),
		get_action_link('action=allowed_html', 'Allowed HTML Tags'),
		get_action_link('action=index', 'List of All Pages'),
		get_action_link('action=locked', 'List of Locked Pages'),
		get_action_link('action=links', 'Link List')
	);
	my @tools = (
		get_action_link('action=ban_list', 'Temple of the Banned'),
		get_action_link('action=link_editor', 'Link Editor')
	);

	if (is_wiki_locked()) {
		push @tools, get_action_link('action=edit_lock&set=0', 'Unlock All');
	} else {
		push @tools, get_action_link('action=edit_lock&set=1', 'Lock All');
	}

	my $template = HTML::Template->new_file('admin.tmpl');
	$template->param(
		info  => convert_array(@info),
		tools => convert_array(@tools)
	);

	print get_header('Administration Panel'), $template->output(), get_footer();
}

sub do_allowed_html {
	my $template = HTML::Template->new_file('htmltags.tmpl');
	$template->param(
		single => convert_array(HTML_SINGLE),
		pairs  => convert_array(HTML_PAIRS)
	);

	print get_header('Allowed HTML Tags'), $template->output(), get_footer();
}

sub do_edit_banlist {
	my $ban_list = '';

	if (open my $handle, '<', join('/', BASE_DIR, DATA_DIR, BAN_LIST)) {
		$ban_list = <$handle>;
		close $handle;
	}

	my $template = HTML::Template->new_file('banlist.tmpl');
	$template->param(
		script_name => SCRIPT_NAME,
		ban_list    => quote_html($ban_list)
	);

	print get_header('Temple of the Banned'), $template->output(), get_footer();
}

sub do_update_banned {
	return 0 if (!is_user_admin_or_error());

	my $ban_list = get_param('banlist', '');

	if ($ban_list) {
		if (open my $handle, '>', join('/', BASE_DIR, DATA_DIR, BAN_LIST)) {
			print $handle $ban_list;
			close $handle;
		} else {
			report_error('Could not write ban list.');
			return 0;
		}
	} else {
		unlink join('/', BASE_DIR, DATA_DIR, BAN_LIST);
	}

	my $template = HTML::Template->new_file('saveban.tmpl');
	$template->param(ban_list => $ban_list);

	print get_header('Temple of the Banned'), $template->output(), get_footer();
	return 1;
}

sub do_edit_links {
	my $template = HTML::Template->new_file('linkeditor.tmpl');
	$template->param(script_name => SCRIPT_NAME);

	print get_header('Link Editor'), $template->output(), get_footer();
}

sub do_update_links {
	return 0 if (!is_user_admin_or_error());

	my $command_list = get_param('commandlist', '');
	my @results = ();

	if ($command_list) {
		my $do_text = get_param('p_changetext', 'off');
		$do_text = 1 if ($do_text eq 'on');

		push @results, update_link_list($command_list, $do_text);
	}

	my $template = HTML::Template->new_file('savelinks.tmpl');
	$template->param(
		command_list => $command_list,
		results      => convert_array(@results)
	);

	print get_header('Link Editor'), $template->output(), get_footer();
	return 1;
}

sub do_edit_lock {
	my $confirm = get_param('confirm', '');

	if ($confirm) {
		return 0 if (!is_user_admin_or_error());

		if (is_wiki_locked()) {
			unlink join('/', BASE_DIR, DATA_DIR, LOCK_ALL);
		} else {
			if (open my $handle, '>', join('/', BASE_DIR, DATA_DIR, LOCK_ALL)) {
				print $handle 'The wiki is locked.';
				close $handle;
			} else {
				report_error('Could not write lock file.');
				return 0;
			}
		}
	}

	my $template = HTML::Template->new_file('globallock.tmpl');
	$template->param(
		script_name => SCRIPT_NAME,
		confirm     => $confirm,
		locked      => is_wiki_locked()
	);

	print get_header('Global Lock'), $template->output(), get_footer();
	return 1;
}

sub do_page_lock {
	my ($id) = @_;

	return 0 if (!is_valid_id_or_error($id));
	return 0 if (!is_user_admin_or_error());

	if (get_param('set', 1)) { # lock
		add_page_meta($id, 'locked', 1);
	} else { # unlock
		delete_page_meta($id, 'locked');
	}

	my $template = HTML::Template->new_file('pagelock.tmpl');
	$template->param(
		lock      => get_param('set', 1),
		page_link => get_page_link($id)
	);

	print get_header('Lock Page'), $template->output(), get_footer($id);
	return 1;
}

sub do_delete_page {
	my ($id) = @_;

	return 0 if (!is_valid_id_or_error($id));

	my $success = 0;

	if (get_param('confirm', '')) {
		return 0 if (!is_user_admin_or_error());

		if ($id ne HOME_PAGE && !is_page_locked($id)) {
			$success = delete_page($id, 1, 1);
		}
	}

	my $template = HTML::Template->new_file('delete.tmpl');
	$template->param(
		script_name => SCRIPT_NAME,
		confirm     => get_param('confirm', ''),
		home_page   => $id eq HOME_PAGE,
		locked      => is_page_locked($id),
		success     => $success,
		page_id     => $id,
		page_link   => get_page_link($id)
	);

	print get_header('Delete Page'), $template->output(), get_footer($id);
	return 1;
}

sub read_theme_metadata {
	my ($theme) = @_;
	my $path = join('/', BASE_DIR, THEME_DIR, $theme);

	open my $handle, '<', "$path/theme.ini"
		or return ();
	my @lines = <$handle>;
	close $handle;

	my %metadata = ();

	for (@lines) {
		my ($key, $value) = split /\s*=\s*/;
		$value =~ s/^"([^"]+)"$/$1/;
		$value =~ s/\s+$//;

		$metadata{$key} = $value;
	}

	return %metadata;
}

################################################################################
# Search functions                                                             #
################################################################################

sub all_pages_list {
	my $page_link = connect_to_page_db()
		or return ();
	my $query = $page_link->prepare('
		SELECT DISTINCT page FROM pagemeta ORDER BY page
	');
	$query->execute();

	my @index = ();

	while (my ($page) = $query->fetchrow_array()) {
		push @index, $page;
	}

	$page_link->disconnect();

	return @index;
}

sub locked_pages_list {
	my $page_link = connect_to_page_db()
		or return ();
	my $query = $page_link->prepare('
		SELECT page FROM pagemeta WHERE entry = ? AND value = ?
	');
	$query->bind_param(1, 'locked', SQL_VARCHAR);
	$query->bind_param(2, 1, SQL_INTEGER);
	$query->execute();

	my @index = ();

	while (my ($page) = $query->fetchrow_array()) {
		push @index, $page;
	}

	$page_link->disconnect();

	return @index;
}

sub page_list {
	my $results = $#_ + 1;
	return map {item => get_page_link($_)}, @_;
}

sub file_list {
	my $results = $#_ + 1;
	return map {item => get_file_link(FILES_DIR . $_)}, @_;
}

sub print_page_list {
	my @list = page_list(@_);
	my $count = @list;

	my $template = HTML::Template->new_file('pagelist.tmpl');
	$template->param(
		pages_found => $count,
		page_count  => $count == 1 ? '1 page' : "$count pages",
		page_list   => \@list
	);

	print $template->output();
}

sub search_pages {
	my ($string) = @_;
	my @found = ();

	$string = quote_regex($string);

	for my $name (all_pages_list()) {
		my %page = open_page($name);
		$page{'text'} ||= '';

		if ($page{'text'} =~ /$string/i || $name =~ /$string/i) {
			push @found, $name;
		} elsif ($name =~ /_/) {
			if (string_page_name($name) =~ /$string/i) {
				push @found, $name;
			}
		}
	}

	return @found;
}

sub search_files {
	my ($string) = @_;
	my @found = ();

	$string = quote_regex($string);

	# searches without spaces
	my $no_spaces = $string;
	$no_spaces =~ s/\s+//g;

	open my $handle, '<', join('/', BASE_DIR, DATA_DIR, FILE_INDEX)
		or return ();

	while (<$handle>) {
		if (/($string|$no_spaces)/i) {
			chomp;
			push @found, $_;
		}
	}

	close $handle;

	return @found;
}

################################################################################
# String functions                                                             #
################################################################################

sub quote_html {
	my ($string) = shift || '';

	$string =~ s/&/&amp;/g;
	$string =~ s/</&lt;/g;
	$string =~ s/>/&gt;/g;
	$string =~ s/&amp;([#a-zA-Z0-9]+);/&$1;/g; # allows character references

	return $string;
}

sub quote_regex {
	my ($string) = shift || '';

	$string =~ s/([-'().,|\^\$\[\]\\\(\)\{\}\*\+\?])/\\$1/g;
	return $string;
}

sub encode_url {
	my ($string) = shift || '';

	$string =~ s|([^-_\w\./:])|'%'.uc(sprintf('%2.2x', ord($1)))|eg;
	return $string;
}

sub encode_arg {
	my ($string) = shift || '';

	$string =~ s|([^-_\w\.])|'%'.uc(sprintf('%2.2x', ord($1)))|eg; # RFC 1738
	return $string;
}

sub string_page_id {
	my ($string) = shift || '';

	$string =~ s/ /_/g;
	return $string;
}

sub string_page_name {
	my ($string) = shift || '';

	$string =~ s/_/ /g;
	return $string;
}

sub free_to_normal {
	my ($id) = @_;

	return '' if (!$id);

	$id = string_page_id($id);
	$id = ucfirst $id if (FORCE_UPPER);

	if (index($id, '_') > -1) { # quick check for any space/underscores
		$id =~ s/__+/_/g;
		$id =~ s/^_//;
		$id =~ s/_$//;
	}

	if (FORCE_UPPER) {
		# letters after ' are not capitalized
		if ($id =~ m|[-_.,\(\)/][a-z]|) { # quick check for non-canonical case
			$id =~ s|([-_.,\(\)/])([a-z])|$1.uc($2)|ge;
		}
	}

	return $id;
}

################################################################################
# Date/time functions                                                          #
################################################################################

sub calc_short_date {
	my ($timestamp) = @_;
	return strftime('%Y/%m/%d', gmtime $timestamp + $TimeZone);
}

sub calc_long_date {
	my ($timestamp) = @_;
	my @date = gmtime $timestamp + $TimeZone;
	my $ordinal = qw(th st nd rd)[$date[3] =~ /(?<!1)([123])$/ ? $1 : 0];

	return strftime("%B %e$ordinal, %Y", @date);
}

sub calc_rss_date {
	return strftime('%a, %d %b %Y %T +0000', gmtime shift); # RFC 822
}

sub calc_day {
	my ($timestamp) = @_;
	my @now = gmtime $Now + $TimeZone;
	my @then = gmtime $timestamp + $TimeZone;

	if ($now[4] == $then[4] && $now[5] == $then[5]) {
		return 'Today' if ($now[3] == $then[3]);
		return 'Yesterday' if (($now[3] - 1) == $then[3]);
	}

	return strftime('%A', @then);
}

sub calc_time {
	my ($timestamp) = @_;

	my $format = '%l:%M %p';
	# adds time zone abbreviation if no offset
	$format .= ' %Z' if ($TimeZone == 0);

	return strftime($format, gmtime $timestamp + $TimeZone);
}

sub time_to_text {
	my ($timestamp) = @_;

	return sprintf(
		'%s, %s at %s',
		calc_day($timestamp),
		calc_long_date($timestamp),
		calc_time($timestamp)
	);
}

do_wiki_request();