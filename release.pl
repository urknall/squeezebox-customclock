#!/usr/bin/perl
use strict;

use XML::Simple;
use File::Basename;
use Digest::SHA;

my $repofile = $ARGV[0];
my $version = $ARGV[1];
my $zipfile = $ARGV[2];
my $url = $ARGV[3];

my $repo = XMLin($repofile, ForceArray => 1, KeepRoot => 0, KeyAttr => 0, NoAttr => 0);
$repo->{applets}[0]->{applet}[0]->{version} = $version;

open (my $fh, "<", $zipfile) or die $!;
binmode $fh;

my $digest = Digest::SHA->new;
$digest->addfile($fh);
close $fh;

$repo->{applets}[0]->{applet}[0]->{sha}[0] = $digest->hexdigest;
print("version: $version\n");
print("sha    : ", $digest->hexdigest, "\n");

$url .= "/$zipfile";
$repo->{applets}[0]->{applet}[0]->{url}[0] = $url;
print("url    : $url");

XMLout($repo, RootName => 'extensions', NoSort => 1, XMLDecl => 1, KeyAttr => '', OutputFile => $repofile, NoAttr => 0);


