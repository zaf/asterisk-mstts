#!/usr/bin/env perl

#
# Script that uses Bing Text To Speech API for speech synthesis.
#
# Copyright (C) 2016, Lefteris Zafiris <zaf@fastmail.com>
#
# This program is free software, distributed under the terms of
# the GNU General Public License Version 2.
#

use warnings;
use strict;
use utf8;
use Encode qw(decode encode);
use Getopt::Long;
use File::Temp qw(tempfile);
use LWP::UserAgent;
use LWP::ConnCache;

# -------------------------------------- #
# Here you can assign your Bing API Key  #
my $key = "";
# -------------------------------------- #

my @text;
my @rawlist;
my $input;
my $file;
my $outfile;
my $quiet;
my $lang       = "en-US";
my $gender     = "Female";
my $format     = "raw-16khz-16bit-mono-pcm";
my $samplerate = 16000;
my $level      = -3;
my $speed      = 1;
my $tmpdir     = "/tmp";
my $timeout    = 15;
my $url        = "https://speech.platform.bing.com/synthesize";
my $sox        = `/usr/bin/which sox`;
my %lang_list  = get_lang_list();

if (!$sox) {
	say_msg("sox is missing. Aborting.");
	exit 1;
}
chomp($sox);

# Parse cli options
Getopt::Long::Configure("bundling", "no_ignore_case", "permute", "no_getopt_compat");
GetOptions (
	"k=s" => \$key,
	"t=s" => \$input,
	"f=s" => \$file,
	"l=s" => \$lang,
	"g=s" => \$gender,
	"r=i" => \$samplerate,
	"o=s" => \$outfile,
	"n=f" => \$level,
	"s=f" => \$speed,
	"q"   => \$quiet,
	"v"   => \&print_lang_list,
	"h"   => \&help_message,
) or help_message();

if ($file) {
	if (open(my $fh, "<", $file)) {
		$input = do { local $/; <$fh> };
		close($fh);
	} else {
		say_msg("Cant read file $file");
	}
}
if ($gender =~ /^m(ale)?$/i) {
	$gender = "Male";
} else {
	$gender = "Female";
}
if (!exists $lang_list{"$lang-$gender"}) {
	say_msg("Unsupported language/gender combination.");
	exit 1;
}

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

# Initialize User agent #
my $ua = LWP::UserAgent->new(ssl_opts => {verify_hostname => 1});
$ua->env_proxy;
$ua->conn_cache(LWP::ConnCache->new());
$ua->timeout($timeout);

my $atoken = get_access_token();

foreach my $line (@text) {
	# Get speech data chunks and save them in temp files #
	$line = encode('utf8', $line);
	$line =~ s/^\s+|\s+$//g;
	next if (length($line) == 0);

	my $data = "<speak version='1.0' xml:lang='" . $lang . "'><voice xml:lang='". $lang
		. "' xml:gender='" . $gender . "' name='" . $lang_list{"$lang-$gender"}
		. "'>" . $line ."</voice></speak>";
	my $ua_response = $ua->post(
		$url,
		"Content-type" => "application/ssml+xml",
		"X-Microsoft-OutputFormat" => $format,
		"Authorization" => $atoken,
		"Content" => $data,
	);
	if (!$ua_response->is_success) {
		say_msg("Failed to fetch file:", $ua_response->status_line);
		exit 1;
	}

	my ($tmpfh, $tmpname) = tempfile(
		"bingtts_XXXXXX",
		SUFFIX => ".raw",
		DIR    => $tmpdir,
		UNLINK => 1,
	);
	binmode $tmpfh;
	print $tmpfh $ua_response->decoded_content( charset => 'none' );
	close $tmpfh;
	push(@rawlist, ('-r', '16000', '-b', '16', '-c', '1', '-e', 'signed-integer', $tmpname));
}

# Set sox args and process sound files #
my @soxargs = ($sox, '-q', "--norm=$level", @rawlist);
if ($outfile) {
	push(@soxargs, ($outfile));
} else {
	push(@soxargs, ('-t', 'alsa', '-d'));
}
push(@soxargs, ('tempo', '-s', $speed)) if ($speed != 1);
push(@soxargs, ('rate', $samplerate)) if ($samplerate != 16000);

if (system(@soxargs)) {
	say_msg("sox failed to process sound file.");
	exit 1;
}

exit 0;

sub get_access_token {
	my $token = '';
	if (!$key) {
		say_msg("No API Key provided.");
		exit 1;
	}
	my $response = $ua->post(
		"https://api.cognitive.microsoft.com/sts/v1.0/issueToken",
		"Ocp-Apim-Subscription-Key" => $key,
	);
	if ($response->is_success) {
		$token = "Bearer " . $response->content;
		} else {
			say_msg("Failed to get Access Token:", $response->status_line);
			exit 1;
		}
	return $token;
}

sub print_lang_list {
	print "Supported Language list:\n";
	print "$_\n" for (keys %lang_list);
	exit 1;
}

sub get_lang_list {
	my %list = (
		"ar-EG-Female"	=> "Microsoft Server Speech Text to Speech Voice (ar-EG, Hoda)",
		"de-DE-Female"	=> "Microsoft Server Speech Text to Speech Voice (de-DE, Hedda)",
		"de-DE-Male"	=> "Microsoft Server Speech Text to Speech Voice (de-DE, Stefan, Apollo)",
		"en-AU-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-AU, Catherine)",
		"en-CA-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-CA, Linda)",
		"en-GB-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-GB, Susan, Apollo)",
		"en-GB-Male"	=> "Microsoft Server Speech Text to Speech Voice (en-GB, George, Apollo)",
		"en-IN-Male"	=> "Microsoft Server Speech Text to Speech Voice (en-IN, Ravi, Apollo)",
		"en-US-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-US, ZiraRUS)",
		"en-US-Male"	=> "Microsoft Server Speech Text to Speech Voice (en-US, BenjaminRUS)",
		"es-ES-Female"	=> "Microsoft Server Speech Text to Speech Voice (es-ES, Laura, Apollo)",
		"es-ES-Male"	=> "Microsoft Server Speech Text to Speech Voice (es-ES, Pablo, Apollo)",
		"es-MX-Male"	=> "Microsoft Server Speech Text to Speech Voice (es-MX, Raul, Apollo)",
		"fr-CA-Female"	=> "Microsoft Server Speech Text to Speech Voice (fr-CA, Caroline)",
		"fr-FR-Female"	=> "Microsoft Server Speech Text to Speech Voice (fr-FR, Julie, Apollo)",
		"fr-FR-Male"	=> "Microsoft Server Speech Text to Speech Voice (fr-FR, Paul, Apollo)",
		"it-IT-Male"	=> "Microsoft Server Speech Text to Speech Voice (it-IT, Cosimo, Apollo)",
		"ja-JP-Female"	=> "Microsoft Server Speech Text to Speech Voice (ja-JP, Ayumi, Apollo)",
		"ja-JP-Male"	=> "Microsoft Server Speech Text to Speech Voice (ja-JP, Ichiro, Apollo)",
		"pt-BR-Male"	=> "Microsoft Server Speech Text to Speech Voice (pt-BR, Daniel, Apollo)",
		"ru-RU-Female"	=> "Microsoft Server Speech Text to Speech Voice (ru-RU, Irina, Apollo)",
		"ru-RU-Male"	=> "Microsoft Server Speech Text to Speech Voice (ru-RU, Pavel, Apollo)",
		"zh-CN-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-CN, HuihuiRUS)",
		"zh-CN-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-CN, Yaoyao, Apollo)",
		"zh-CN-Male"	=> "Microsoft Server Speech Text to Speech Voice (zh-CN, Kangkang, Apollo)",
		"zh-HK-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-HK, Tracy, Apollo)",
		"zh-HK-Male"	=> "Microsoft Server Speech Text to Speech Voice (zh-HK, Danny, Apollo)",
		"zh-TW-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-TW, Yating, Apollo)",
		"zh-TW-Male"	=> "Microsoft Server Speech Text to Speech Voice (zh-TW, Zhiwei, Apollo)",
	);
	return %list;
}

sub say_msg {
	# Print messages to stderr if 'quiet' flag is not set #
	my $message = join(" ", @_);
	warn "$message\n" if (!$quiet);
	return;
}

sub help_message {
	print "\nText to speech synthesis using Bing TTS API.\n\n",
		"Supported options:\n",
		" -t <text>      text string to synthesize\n",
		" -f <file>      text file to synthesize\n",
		" -l <lang>      specify the language to use, defaults to 'en-US' (US English)\n",
		" -g <gender>    specify the voice gender, defaults to 'f' (female)\n",
		" -r <rate>      specify the output sampling rate in Hertz (default 16000)\n",
		" -o <filename>  save output as file\n",
		" -n <dB-level>  normalize the audio to the given level (default -3)\n",
		" -s <factor>    specify the speech rate speed factor (default 1.0)\n",
		" -k <key>       set the Bing API key\n",
		" -q             quiet (Don't print any messages or warnings)\n",
		" -h             this help message\n",
		" -v             supported languages list\n\n",
		"Examples:\n",
		"$0 -t \"Hello world\"\n\tHave the synthesized speech played back to the user.\n",
		"$0 -o hello.wav -l en-GB -t \"Hello world\"\n\tSave the synthesized speech as a sound file.\n\n";
	exit 1;
}
