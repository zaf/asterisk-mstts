#!/usr/bin/env perl

#
# Script that uses Microsoft Translator for text to speech synthesis.
#
# Copyright (C) 2012 - 2014, Lefteris Zafiris <zaf.000@gmail.com>
#
# This program is free software, distributed under the terms of
# the GNU General Public License Version 2.
#
# In order to use this script you have to subscribe to the Microsoft
# Translator API on Azure Marketplace and register your application:
# https://datamarket.azure.com/developer/applications/
#


use warnings;
use strict;
use Encode qw(decode encode);
use Getopt::Std;
use File::Temp qw(tempfile);
use URI::Escape;
use LWP::UserAgent;
use LWP::ConnCache;

# --------------------------------------- #
# Here you can assing your client ID and  #
# client secret from Azure Marketplace.   #
my $clientid     = "";
my $clientsecret = "";
# --------------------------------------- #

my %options;
my $input;
my @text;
my $tmpfh;
my $tmpname;
my @mp3list;
my $samplerate;
my @soxargs;
my $atoken;
my $lang    = "en";
my $format  = "audio/mp3";
my $quality = "MaxQuality";
my $level   = -3;
my $speed   = 1;
my $tmpdir  = "/tmp";
my $timeout = 15;
my $url     = "https://api.microsofttranslator.com/V2/Http.svc";
my $mpg123  = `/usr/bin/which mpg123`;
my $sox     = `/usr/bin/which sox`;

VERSION_MESSAGE() if (!@ARGV);

getopts('o:l:t:r:f:n:s:c:hqv', \%options);

# Dislpay help messages #
VERSION_MESSAGE() if (defined $options{h});

if (!$mpg123 || !$sox) {
	say_msg("mpg123 or sox is missing. Aborting.");
	exit 1;
}
chomp($mpg123, $sox);

# Initialise User angent #
my $ua = LWP::UserAgent->new(ssl_opts => {verify_hostname => 1});
$ua->env_proxy;
$ua->conn_cache(LWP::ConnCache->new());
$ua->timeout($timeout);

($clientid, $clientsecret) = split(/:/, $options{c}, 2) if (defined $options{c});
$atoken = get_access_token();

if (!$atoken) {
	say_msg("You must have a client ID from Azure Marketplace to use this script.");
	exit 1;
}

parse_options();

$input = decode('utf8', $input);
for ($input) {
	# Split input to chunks of 1000 chars #
	s/[\\|*~<>^\n\(\)\[\]\{\}[:cntrl:]]/ /g;
	s/\s+/ /g;
	s/^\s|\s$//g;
	if (!length) {
		say_msg("No text passed for synthesis.");
		exit 1;
	}
	$_ .= "." unless (/^.+[.,?!:;]$/);
	@text = /.{1,1000}[.,?!:;]|.{1,1000}\s/g;
}

foreach my $line (@text) {
	# Get speech data chunks and save them in temp files #
	$line = encode('utf8', $line);
	$line =~ s/^\s+|\s+$//g;
	next if (length($line) == 0);
	$line = uri_escape($line);

	($tmpfh, $tmpname) = tempfile(
		"mstts_XXXXXX",
		SUFFIX => ".mp3",
		DIR    => $tmpdir,
		UNLINK => 1,
	);

	my $request = HTTP::Request->new('GET' =>
		"$url/Speak?appid=$atoken&text=$line&language=$lang&format=$format&options=$quality"
	);
	my $response = $ua->request($request, $tmpname);
	if (!$response->is_success) {
		say_msg("Failed to fetch speech data!");
		exit 1;
	} else {
		push(@mp3list, $tmpname);
	}
}

# decode mp3s and concatenate #
my ($wavfh, $wavname) = tempfile(
	"mstts_XXXXXX",
	SUFFIX => ".wav",
	DIR    => $tmpdir,
	UNLINK => 1
);
if (system($mpg123, "-q", "-w", $wavname, @mp3list)) {
	say_msg("mpg123 failed to process sound file.");
	exit 1;
}

# Set sox args and process wav file #
@soxargs = ($sox, "-q", "--norm=$level", $wavname);
defined $options{o} ? push(@soxargs, ($options{o})) : push(@soxargs, ("-t", "alsa", "-d"));
push(@soxargs, ("tempo", "-s", $speed)) if ($speed != 1);
push(@soxargs, ("rate", $samplerate)) if ($samplerate);

if (system(@soxargs)) {
	say_msg("sox failed to process sound file.");
	exit 1;
}

exit 0;

sub get_access_token {
	# Obtaining an Access Token #
	my $token;
	my $response = $ua->post(
		"https://datamarket.accesscontrol.windows.net/v2/OAuth2-13/",
		[
			client_id     => $clientid,
			client_secret => $clientsecret,
			scope         => 'http://api.microsofttranslator.com',
			grant_type    => 'client_credentials',
		],
	);
	if ($response->is_success and $response->content =~ /^\{"token_type":".+?","access_token":"(.+?)","expires_in":".+?","scope":".+?"\}$/) {
		$token = uri_escape("Bearer $1");
	} else {
		say_msg("Failed to get Access Token.");
	}
	return $token;
}

sub parse_options {
	lang_list() if (defined $options{v});
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
	# check if language setting is valid #
	if (defined $options{l}) {
		$options{l} =~ /^[a-zA-Z]{2}(-[a-zA-Z]{2,3})?$/ ? $lang = $options{l}
			: say_msg("Invalid language setting, using default.");
	}
	# set audio sample rate #
	if (defined $options{r}) {
		$options{r} =~ /\d+/ ? $samplerate = $options{r}
			: say_msg("Invalid sample rate, using default.");
	}
	# set speed factor #
	if (defined $options{s}) {
		$options{s} =~ /\d+/ ? $speed = $options{s}
			: say_msg("Invalind speed factor, using default.");
	}
	# set the audio normalisation level #
	if (defined $options{n}) {
		$options{n} =~ /\d+/ ? $level = $options{n}
			: say_msg("Invalind normalisation level, using default.");
	}
	return;
}

sub lang_list {
	# Display the list of supported languages #
	my $request = HTTP::Request->new('GET' => "$url/GetLanguagesForSpeak?appid=$atoken");
	my $response = $ua->request($request);
	if ($response->is_success) {
		print "Supported languages list:\n",
			join("\n", grep(/[a-zA-Z\-]{2,}/, split(/<.+?>/, $response->content))), "\n";
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
		" -n <dB-level>  normalise the audio to the given level (default -3)\n",
		" -s <factor>    specify the speech rate speed factor (default 1.0)\n",
		" -c <clientid>  set the Azure marketplace credentials (clientid:clientsecret)\n",
		" -q             quiet (Don't print any messages or warnings)\n",
		" -h             this help message\n",
		" -v             suppoted languages list\n\n",
		"Examples:\n",
		"$0 -l en -t \"Hello world\"\n\tHave the synthesized speech played back to the user.\n",
		"$0 -o hello.wav -l en -t \"Hello world\"\n\tSave the synthesized speech as a sound file.\n\n";
	exit 1;
}
