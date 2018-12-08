#!/usr/bin/env perl

#
# Script that uses Azure Cognitive Services for speech synthesis.
#
# Copyright (C) 2018, Lefteris Zafiris <zaf@fastmail.com>
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
my $region     = "westus";
my $format     = "raw-16khz-16bit-mono-pcm";
my $samplerate = 16000;
my $level      = -3;
my $speed      = 1;
my $timeout    = 15;
my $url        = "https://" . $region . ".tts.speech.microsoft.com/cognitiveservices/v1";
my %lang_list  = get_lang_list();
my $sox        = `/usr/bin/which sox`;

fatal("sox is missing. Aborting.") if (!$sox);
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

fatal("No API Key provided.") if (!$key);
if ($file) {
	if (open(my $fh, "<", $file)) {
		$input = do { local $/; <$fh> };
		close($fh);
	} else {
		fatal("Cant read file $file");
	}
}
if ($gender =~ /^m(ale)?$/i) {
	$gender = "Male";
} else {
	$gender = "Female";
}
fatal("Unsupported language/gender combination.") if (!exists $lang_list{"$lang-$gender"});

$input = decode('utf8', $input);
for ($input) {
	# Split input to chunks of 1000 chars #
	s/[\\|*~<>^\n\(\)\[\]\{\}[:cntrl:]]/ /g;
	s/\s+/ /g;
	s/^\s|\s$//g;
	@text = /.{1,1000}$|.{1,1000}[.,?!:;]|.{1,1000}\s/g;
}
fatal("No text passed for synthesis.") if (!length($text[0]));

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
	fatal("Failed to fetch file:", $ua_response->status_line) if (!$ua_response->is_success);

	my ($tmpfh, $tmpname) = tempfile(
		"bingtts_XXXXXX",
		SUFFIX => ".raw",
		TMPDIR => 1,
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

fatal("sox failed to process sound file.") if (system(@soxargs));
exit 0;

sub get_access_token {
	my $response = $ua->post(
		"https://" . $region . ".api.cognitive.microsoft.com/sts/v1.0/issueToken",
		"Ocp-Apim-Subscription-Key" => $key,
	);
	fatal("Failed to get Access Token:", $response->status_line) if (!$response->is_success);
	return"Bearer " . $response->content;
}

sub print_lang_list {
	print "Supported Language list:\n";
	print "$_\n" for (keys %lang_list);
	exit 1;
}

sub say_msg {
	# Print messages to stderr if 'quiet' flag is not set #
	my $message = join(" ", @_);
	warn "$message\n" if (!$quiet);
	return;
}

sub fatal {
	say_msg(@_);
	exit 1;
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

sub get_lang_list {
	my %list = (
		"ar-EG-Female"	=> "Microsoft Server Speech Text to Speech Voice (ar-EG, Hoda)",
		"ar-SA-Male"	=> "Microsoft Server Speech Text to Speech Voice (ar-SA, Naayf)",
		"bg-BG-Male"	=> "Microsoft Server Speech Text to Speech Voice (bg-BG, Ivan)",
		"ca-ES-Female"	=> "Microsoft Server Speech Text to Speech Voice (ca-ES, HerenaRUS)",
		"cs-CZ-Male"	=> "Microsoft Server Speech Text to Speech Voice (cs-CZ, Jakub)",
		"da-DK-Female"	=> "Microsoft Server Speech Text to Speech Voice (da-DK, HelleRUS)",
		"de-AT-Male"	=> "Microsoft Server Speech Text to Speech Voice (de-AT, Michael)",
		"de-CH-Male"	=> "Microsoft Server Speech Text to Speech Voice (de-CH, Karsten)",
		"de-DE-Female"	=> "Microsoft Server Speech Text to Speech Voice (de-DE, Hedda)",
		"de-DE-Female"	=> "Microsoft Server Speech Text to Speech Voice (de-DE, HeddaRUS)",
		"de-DE-Male"	=> "Microsoft Server Speech Text to Speech Voice (de-DE, Stefan, Apollo)",
		"el-GR-Male"	=> "Microsoft Server Speech Text to Speech Voice (el-GR, Stefanos)",
		"en-AU-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-AU, Catherine)",
		"en-AU-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-AU, HayleyRUS)",
		"en-CA-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-CA, Linda)",
		"en-CA-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-CA, HeatherRUS)",
		"en-GB-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-GB, Susan, Apollo)",
		"en-GB-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-GB, HazelRUS)",
		"en-GB-Male"	=> "Microsoft Server Speech Text to Speech Voice (en-GB, George, Apollo)",
		"en-IE-Male"	=> "Microsoft Server Speech Text to Speech Voice (en-IE, Sean)",
		"en-IN-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-IN, Heera, Apollo)",
		"en-IN-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-IN, PriyaRUS)",
		"en-IN-Male"	=> "Microsoft Server Speech Text to Speech Voice (en-IN, Ravi, Apollo)",
		"en-US-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-US, ZiraRUS)",
		"en-US-Female"	=> "Microsoft Server Speech Text to Speech Voice (en-US, JessaRUS)",
		"en-US-Male"	=> "Microsoft Server Speech Text to Speech Voice (en-US, BenjaminRUS)",
		"es-ES-Female"	=> "Microsoft Server Speech Text to Speech Voice (es-ES, Laura, Apollo)",
		"es-ES-Female"	=> "Microsoft Server Speech Text to Speech Voice (es-ES, HelenaRUS)",
		"es-ES-Male"	=> "Microsoft Server Speech Text to Speech Voice (es-ES, Pablo, Apollo)",
		"es-MX-Female"	=> "Microsoft Server Speech Text to Speech Voice (es-MX, HildaRUS)",
		"es-MX-Male"	=> "Microsoft Server Speech Text to Speech Voice (es-MX, Raul, Apollo)",
		"fi-FI-Female"	=> "Microsoft Server Speech Text to Speech Voice (fi-FI, HeidiRUS)",
		"fr-CA-Female"	=> "Microsoft Server Speech Text to Speech Voice (fr-CA, Caroline)",
		"fr-CA-Female"	=> "Microsoft Server Speech Text to Speech Voice (fr-CA, HarmonieRUS)",
		"fr-CH-Male"	=> "Microsoft Server Speech Text to Speech Voice (fr-CH, Guillaume)",
		"fr-FR-Female"	=> "Microsoft Server Speech Text to Speech Voice (fr-FR, Julie, Apollo)",
		"fr-FR-Female"	=> "Microsoft Server Speech Text to Speech Voice (fr-FR, HortenseRUS)",
		"fr-FR-Male"	=> "Microsoft Server Speech Text to Speech Voice (fr-FR, Paul, Apollo)",
		"he-IL-Male"	=> "Microsoft Server Speech Text to Speech Voice (he-IL, Asaf)",
		"hi-IN-Female"	=> "Microsoft Server Speech Text to Speech Voice (hi-IN, Kalpana, Apollo)",
		"hi-IN-Female"	=> "Microsoft Server Speech Text to Speech Voice (hi-IN, Kalpana)",
		"hi-IN-Male"	=> "Microsoft Server Speech Text to Speech Voice (hi-IN, Hemant)",
		"hr-HR-Male"	=> "Microsoft Server Speech Text to Speech Voice (hr-HR, Matej)",
		"hu-HU-Male"	=> "Microsoft Server Speech Text to Speech Voice (hu-HU, Szabolcs)",
		"id-ID-Male"	=> "Microsoft Server Speech Text to Speech Voice (id-ID, Andika)",
		"it-IT-Male"	=> "Microsoft Server Speech Text to Speech Voice (it-IT, Cosimo, Apollo)",
		"ja-JP-Female"	=> "Microsoft Server Speech Text to Speech Voice (ja-JP, Ayumi, Apollo)",
		"ja-JP-Male"	=> "Microsoft Server Speech Text to Speech Voice (ja-JP, Ichiro, Apollo)",
		"ja-JP-Female"	=> "Microsoft Server Speech Text to Speech Voice (ja-JP, HarukaRUS)",
		"ja-JP-Female"	=> "Microsoft Server Speech Text to Speech Voice (ja-JP, LuciaRUS)",
		"ja-JP-Male"	=> "Microsoft Server Speech Text to Speech Voice (ja-JP, EkaterinaRUS)",
		"ko-KR-Female"	=> "Microsoft Server Speech Text to Speech Voice (ko-KR, HeamiRUS)",
		"ms-MY-Male"	=> "Microsoft Server Speech Text to Speech Voice (ms-MY, Rizwan)",
		"nb-NO-Female"	=> "Microsoft Server Speech Text to Speech Voice (nb-NO, HuldaRUS)",
		"nl-NL-Female"	=> "Microsoft Server Speech Text to Speech Voice (nl-NL, HannaRUS)",
		"pl-PL-Female"	=> "Microsoft Server Speech Text to Speech Voice (pl-PL, PaulinaRUS)",
		"pt-BR-Female"	=> "Microsoft Server Speech Text to Speech Voice (pt-BR, HeloisaRUS)",
		"pt-BR-Male"	=> "Microsoft Server Speech Text to Speech Voice (pt-BR, Daniel, Apollo)",
		"pt-PT-Female"	=> "Microsoft Server Speech Text to Speech Voice (pt-PT, HeliaRUS)",
		"ro-RO-Male"	=> "Microsoft Server Speech Text to Speech Voice (ro-RO, Andrei)",
		"ru-RU-Female"	=> "Microsoft Server Speech Text to Speech Voice (ru-RU, Irina, Apollo)",
		"ru-RU-Male"	=> "Microsoft Server Speech Text to Speech Voice (ru-RU, Pavel, Apollo)",
		"sk-SK-Male"	=> "Microsoft Server Speech Text to Speech Voice (sk-SK, Filip)",
		"sl-SI-Male"	=> "Microsoft Server Speech Text to Speech Voice (sl-SI, Lado)",
		"sv-SE-Female"	=> "Microsoft Server Speech Text to Speech Voice (sv-SE, HedvigRUS)",
		"ta-IN-Male"	=> "Microsoft Server Speech Text to Speech Voice (ta-IN, Valluvar)",
		"th-TH-Male"	=> "Microsoft Server Speech Text to Speech Voice (th-TH, Pattara)",
		"tr-TR-Female"	=> "Microsoft Server Speech Text to Speech Voice (tr-TR, SedaRUS)",
		"vi-VN-Male"	=> "Microsoft Server Speech Text to Speech Voice (vi-VN, An)",
		"zh-CN-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-CN, HuihuiRUS)",
		"zh-CN-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-CN, Yaoyao, Apollo)",
		"zh-CN-Male"	=> "Microsoft Server Speech Text to Speech Voice (zh-CN, Kangkang, Apollo)",
		"zh-HK-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-HK, Tracy, Apollo)",
		"zh-HK-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-HK, TracyRUS)",
		"zh-HK-Male"	=> "Microsoft Server Speech Text to Speech Voice (zh-HK, Danny, Apollo)",
		"zh-TW-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-TW, Yating, Apollo)",
		"zh-TW-Female"	=> "Microsoft Server Speech Text to Speech Voice (zh-TW, HanHanRUS)",
		"zh-TW-Male"	=> "Microsoft Server Speech Text to Speech Voice (zh-TW, Zhiwei, Apollo)",
	);
	return %list;
}

