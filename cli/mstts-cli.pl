#!/usr/bin/env perl

#
# Script that uses Microsoft Translator for text to speech synthesis.
#
# In order to use this script an API Key (appid)
# from http://www.bing.com/developers/appids.aspx is needed.
#
# Copyright (C) 2012, Lefteris Zafiris <zaf.000@gmail.com>
#
# This program is free software, distributed under the terms of
# the GNU General Public License Version 2.
#

use warnings;
use strict;
use Getopt::Std;
use File::Copy qw(move);
use File::Temp qw(tempfile);
use CGI::Util qw(escape);
use LWP::UserAgent;

# --------------------------------------- #
# Here you can assign your App ID from MS #
my $appid   = "";
# --------------------------------------- #
my %options;
my $input;
my $ua;
my $request;
my $response;
my $mp3fh;
my $mp3name;
my $lang    = "en";
my $format  = "audio/mp3";
my $tmpdir  = "/tmp";
my $timeout = 10;
my $url     = "http://api.microsofttranslator.com/V2/Http.svc";
my $mpg123  = `/usr/bin/which mpg123`;

VERSION_MESSAGE() if (!@ARGV);

getopts('o:l:t:f:i:hqv', \%options);

# Dislpay help messages #
VERSION_MESSAGE() if (defined $options{h});
lang_list() if (defined $options{v});

if (!$mpg123) {
	say_msg("mpg123 is missing. Aborting.");
	exit 1;
}
chomp($mpg123);


$appid = $options{i} if (defined $options{i});
if (!$appid) {
	say_msg("You must have an App ID from Microsoft to use this script.");
	exit 1;
}

if (defined $options{l}) {
# check if language setting is valid #
	if ($options{l} =~ /\w+/) {
		$lang = $options{l};
	} else {
		say_msg("Invalid language setting. Aborting.");
		exit 1;
	}
}

$format = "audio/wav" if (defined $options{o});

# Get input text #
if (defined $options{t}) {
	$input = $options{t};
} elsif (defined $options{f}) {
	if (open(my $fh, "<", "$options{f}")) {
		$input = do { local $/; <$fh> };
		close($fh);
	} else {
		say_msg("Cant read file $options{f}");
		exit 1;
	}
} else {
	say_msg("No text passed for synthesis.");
	exit 1;
}

for ($input) {
	s/[\\|*~<>^\n\(\)\[\]\{\}[:cntrl:]]/ /g;
	s/\s+/ /g;
	s/^\s|\s$//g;
	if (!length) {
		say_msg("No text passed for synthesis.");
		exit 1;
	}
	$_ = escape($_);
}

$ua = LWP::UserAgent->new;
$ua->agent("Mozilla/5.0 (X11; Linux; rv:8.0) Gecko/20100101");
$ua->timeout($timeout);

$request = HTTP::Request->new(
	'GET' => "$url/Speak?text=$input&language=$lang&format=$format&options=MaxQuality&appid=$appid"
);

$response = $ua->request($request);
if (!$response->is_success) {
	say_msg("Failed to fetch speech data.");
	exit 1;
} else {
	($mp3fh, $mp3name) = tempfile(
		"mstts_XXXXXX",
		SUFFIX => ".mp3",
		DIR    => $tmpdir,
		UNLINK => 1,
	);
	if (!open($mp3fh, ">", "$mp3name")) {
		say_msg("Cant read temp file $mp3name");
		exit 1;
	}
	print $mp3fh $response->content;
	close $mp3fh;
}

# Set mpg123 args and process sound file #
if (defined $options{o}) {
	move("$mp3name", "$options{o}");
} elsif (system($mpg123, "-q", "$mp3name")) {
	say_msg("Failed to process sound file.");
	exit 1;
}
exit 0;

sub say_msg {
# Print messages to user if 'quiet' flag is not set #
	my $message = shift;
	warn "$0: $message" if (!defined $options{q});
	return;
}

sub VERSION_MESSAGE {
# Help message #
	print "Text to speech synthesis using Microsoft Translator API.\n\n",
		 "Supported options:\n",
		 " -t <text>      text string to synthesize\n",
		 " -f <file>      text file to synthesize\n",
		 " -l <lang>      specify the language to use, defaults to 'en' (English)\n",
		 " -o <filename>  write output as wav file\n",
		 " -i <appID>     set the App ID from MS\n",
		 " -q             quiet (Don't print any messages or warnings)\n",
		 " -h             this help message\n",
		 " -v             suppoted languages list\n\n",
		 "Examples:\n",
		 "$0 -l en -t \"Hello world\"\n Have the synthesized speech played back to the user.\n",
		 "$0 -o hello.wav -l en -t \"Hello world\"\n Save the synthesized speech as a wav file.\n\n";
	exit 1;
}

sub lang_list {
# Display the list of supported languages #
	$ua = LWP::UserAgent->new;
	$ua->agent("Mozilla/5.0 (X11; Linux; rv:8.0) Gecko/20100101");
	$ua->timeout($timeout);
	$request = HTTP::Request->new('GET' => "$url/GetLanguagesForSpeak?appid=$appid");
	$response = $ua->request($request);
	if (!$response->is_success) {
		say_msg("Failed to fetch language list.");
	} else {
		my @list = split(/<string>([a-z\-]*?)<\/string>/,$response->content);
		print "$_\t" foreach (@list[1..($#list-1)]);
		print "\n";
	}
	exit 1;
}
