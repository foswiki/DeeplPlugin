# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# DeeplPlugin is Copyright (C) 2021-2024 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::DeeplPlugin;

=begin TML

---+ package Foswiki::Plugins::DeeplPlugin

base class to hook into the foswiki core

=cut

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Contrib::JsonRpcContrib ();

our $VERSION = '1.00';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'Deepl translation service for Foswiki';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

initialize the plugin, automatically called during the core initialization process

=cut

sub initPlugin {

  return 0 unless $Foswiki::cfg{DeeplPlugin}{APIKey};

  Foswiki::Func::registerTagHandler('DEEPL', sub { return getCore(shift)->DEEPL(@_); });
  Foswiki::Func::registerTagHandler('DEEPL_LANGUAGES', sub { return getCore(shift)->DEEPL_LANGUAGES(@_); });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("DeeplPlugin", "translate", sub {
    return getCore()->jsonRpcTranslate(@_);
  });

  Foswiki::Plugins::JQueryPlugin::registerPlugin('Deepl', 'Foswiki::Plugins::DeeplPlugin::JQUERY');

  return 1;
}

=begin TML

---++ getCore() -> $core

returns a singleton Foswiki::Plugins::DeepPlugin::Core object for this plugin; a new core is allocated 
during each session request; once a core has been created it is destroyed during =finishPlugin()=

=cut

sub getCore {
  
  unless (defined $core) {
    require Foswiki::Plugins::DeeplPlugin::Core;
    $core = Foswiki::Plugins::DeeplPlugin::Core->new(shift);
  }

  return $core;
}

=begin TML

---++ finishPlugin

finish the plugin and the core if it has been used,
automatically called during the core initialization process

=cut

sub finishPlugin {
  undef $core;
}

=begin TML

---++ ObjectMethod commonTagsHandler($text, $topic, $web, $included, $meta) 

hook into the macro parser, adds the %STARTDEEPL .... %ENDDEEPL sectional translations.

=cut

sub commonTagsHandler {
# my ($text, $topic, $web, $included, $meta ) = @_;
  $_[0] =~ s/%STARTDEEPL\{(.*?)\}%(.*?)%ENDDEEPL%/&_handleDeeplSection($1, $2, $_[2], $_[1])/ges;
}

sub _handleDeeplSection {
  return getCore()->handleDeeplSection(@_);
}

=begin TML

---++ afterSaveHandler($text, $topic, $web, $error, $meta )

translate a topic as part of a save action

TODO: translate comments of attachments

=cut

sub afterSaveHandler {
  my (undef, $topic, $web, $error, $meta) = @_;

  return if $error;

  my $request = Foswiki::Func::getRequestObject();

  my $doTranslate = Foswiki::Func::isTrue($request->param("deepl_translate"), 0);
  return unless $doTranslate;

  $request->delete("deepl_translate");
  $request->delete("Set+BASETRANSLATION");

  my @fields = $request->multi_param("translate_fields");
  return unless @fields;
  $request->delete("translate_fields");

  my $targetLang = $request->param("Set+CONTENT_LANGUAGE");
  return unless $targetLang;

  my $sourceLang = $request->param("source_lang") // getCore()->userLanguage();
  $request->delete("source_lang");

  if (getCore()->translateTopic($meta, $sourceLang, $targetLang, join(", ", @fields))) {

    $meta->saveAs();

    # set content lanugage of source
    my $source = $request->param("templatetopic");
    return unless $source;
    $request->delete("templatetopic");

    my ($sourceWeb, $sourceTopic) = Foswiki::Func::normalizeWebTopicName($web, $source);
    my ($sourceMeta) = Foswiki::Func::readTopic($sourceWeb, $sourceTopic);

    my $lang = $sourceMeta->get("PREFERENCE", "CONTENT_LANGUAGE");
    $lang = $lang->{value} if defined $lang;
    return if $lang && $lang eq $sourceLang;

    my $wikiName = Foswiki::Func::getWikiName();
    return unless Foswiki::Func::checkAccessPermission("CHANGE", $wikiName, undef, $sourceTopic, $sourceWeb, $sourceMeta);

    $sourceMeta->putKeyed('PREFERENCE', {
      name  => "CONTENT_LANGUAGE",
      title => "CONTENT_LANGUAGE",
      type  => 'Local',
      value => $sourceLang,
    });

    $sourceMeta->saveAs();
    if (Foswiki::Func::getContext()->{DBCachePluginEnabled}) {
      require Foswiki::Plugins::DBCachePlugin;
      Foswiki::Plugins::DBCachePlugin::getCore()->afterSaveHandler($sourceWeb, $sourceTopic);
    }
  }
}

1;
