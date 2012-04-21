#!/usr/bin/env perl

#
# Script that uses Microsoft Translator for text to speech synthesis.
#
# In order to use this script you have to subscribe to the Microsoft
# Translator API on Azure Marketplace:
# https://datamarket.azure.com/developer/applications/
#
# Existing API Keys from http://www.bing.com/developers/appids.aspx
# still work but they are considered deprecated and this method
# is no longer supported.
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
# Here you can assing your client ID and  #
# client secret from Azure Marketplace.   #
my $clientid = "";
my $clientsecret = "";

#         ****DEPRECATED****              #
# Here you can assign your Bing App ID    #
my $appid   = "";
#         ****DEPRECATED****              #
# --------------------------------------- #

my %options;
my $input;
my $tmpfh;
my $tmpname;
my $samplerate;
my @soxargs;
my $lang    = "en";
my $format  = "audio/wav";
my $tmpdir  = "/tmp";
my $timeout = 15;
my $url     = "http://api.microsofttranslator.com/V2/Http.svc";
my $sox     = `/usr/bin/which sox`;

VERSION_MESSAGE() if (!@ARGV);

getopts('o:l:t:r:f:c:i:hqv', \%options);

# Dislpay help messages #
VERSION_MESSAGE() if (defined $options{h});

if (!$sox) {
	say_msg("sox is missing. Aborting.");
	exit 1;
}
chomp($sox);

$appid = $options{i} if (defined $options{i});
($clientid, $clientsecret) = split(/:/, $options{c}, 2) if (defined $options{c});
$appid = get_access_token() if (!$appid);

if (!$appid) {
	say_msg("You must have a client ID from Azure Marketplace or a Bing AppID to use this script.");
	exit 1;
}

lang_list() if (defined $options{v});

if (defined $options{l}) {
# check if language setting is valid #
	if ($options{l} =~ /\w+/) {
		$lang = $options{l};
	} else {
		say_msg("Invalid language setting. Aborting.");
		exit 1;
	}
}

if (defined $options{r}) {
# set audio sample rate #
	if ($options{r} =~ /\d+/) {
		$samplerate = $options{r};
	} else {
		say_msg("Invalid sample rate, using default.");
	}
}

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

my $ua = LWP::UserAgent->new;
$ua->env_proxy;
$ua->timeout($timeout);

($tmpfh, $tmpname) = tempfile(
	"mstts_XXXXXX",
	SUFFIX => ".wav",
	DIR    => $tmpdir,
	UNLINK => 1,
);
my $request = HTTP::Request->new(
	'GET' => "$url/Speak?appid=$appid&text=$input&language=$lang&format=$format&options=MaxQuality"
);
my $response = $ua->request($request, $tmpname);
if (!$response->is_success) {
	say_msg("Failed to fetch speech data.");
	exit 1;
}

# Set sox args and process wav file #
if (defined $options{o}) {
	@soxargs = ($sox, "-q", $tmpname, $options{o});
	push(@soxargs, ("rate", $samplerate)) if ($samplerate);
} else {
	@soxargs = ($sox, "-q", $tmpname, "-t", "alsa", "-d");
}

if (system(@soxargs)) {
	say_msg("sox failed to process sound file.");
	exit 1;
}

exit 0;

sub get_access_token {
# Obtaining an Access Token #
	my $ua = LWP::UserAgent->new(ssl_opts => {verify_hostname => 1});
	$ua->timeout($timeout);
	my $response = $ua->post(
		"https://datamarket.accesscontrol.windows.net/v2/OAuth2-13/",
		[
			client_id     => $clientid,
			client_secret => $clientsecret,
			scope         => 'http://api.microsofttranslator.com',
			grant_type    => 'client_credentials',
		],
	);
	if ($response->is_success) {
		$response->content =~ /^\{"access_token":"(.*?)","token_type":".*"\}$/;
		my $token = escape("Bearer $1");
		return("$token");
	} else {
		say_msg("Failed to get Access Token.");
		return("");
	}
}

sub lang_list {
# Display the list of supported languages #
	my $ua = LWP::UserAgent->new;
	$ua->env_proxy;
	$ua->timeout($timeout);
	my $request = HTTP::Request->new('GET' => "$url/GetLanguagesForSpeak?appid=$appid");
	my $response = $ua->request($request);
	if ($response->is_success) {
		print "Supported languages list:\n",
			join("\n", grep(/[a-z\-]{2,}/, split(/<.+?>/, $response->content))), "\n";
	} else {
		say_msg("Failed to fetch language list.");
	}
	exit 1;
}

sub say_msg {
# Print messages to user if 'quiet' flag is not set #
	my @message = @_;
	warn @message if (!defined $options{q});
	return;
}

sub VERSION_MESSAGE {
# Help message #
	print "Text to speech synthesis using Microsoft Translator API.\n\n",
		"In order to use this script you have to subscribe to the Microsoft\n",
		"Translator API on Azure Marketplace:\n",
		"https://datamarket.azure.com/developer/applications/\n",
		"Existing API Keys from http://www.bing.com/developers/appids.aspx\n",
		"still work but they are considered deprecated and this method is no longer supported.\n\n",
		 "Supported options:\n",
		 " -t <text>      text string to synthesize\n",
		 " -f <file>      text file to synthesize\n",
		 " -l <lang>      specify the language to use, defaults to 'en' (English)\n",
		 " -r <rate>      specify the output sampling rate in Hertz (default 16000)\n",
		 " -o <filename>  save output as file\n",
		 " -c <clientid>  set the Azure marketplace credentials (clientid:clientsecret)\n",
		 " -i <appID>     set the Bing App ID\n",
		 " -q             quiet (Don't print any messages or warnings)\n",
		 " -h             this help message\n",
		 " -v             suppoted languages list\n\n",
		 "Examples:\n",
		 "$0 -l en -t \"Hello world\"\n\tHave the synthesized speech played back to the user.\n",
		 "$0 -o hello.wav -l en -t \"Hello world\"\n\tSave the synthesized speech as a sound file.\n\n";
	exit 1;
}
