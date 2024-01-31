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

package Foswiki::Plugins::DeeplPlugin::Core;

=begin TML

---+ package Foswiki::Plugins::DeeplPlugin::Core

core class for this plugin

an singleton instance is allocated on demand

=cut

use strict;
use warnings;

use Error qw(:try);
use Foswiki::Func ();
use Foswiki::Contrib::CacheContrib ();
use Encode ();
use Foswiki::Plugins ();

use constant TRACE => 0; # toggle me
#use Data::Dump qw(dump);

our %LANGUAGE_MAPPING = (
  "zh-cn" => "zh",
  "zh" => "zh-cn",
);

use constant DEEPL_PARAMS => qw(
  text 
  source_lang 
  target_lang 
  context
  split_sentences 
  preserve_formatting 
  formality 
  glossary_id
  tag_handling
  outline_detection
  non_splitting_tags
  splitting_tags
  ignore_tags
);

=begin TML

---++ ClassMethod new() -> $core

constructor for a Core object

=cut

sub new {
  my $class = shift;
  my $session = shift;

  $session //= $Foswiki::Plugins::SESSION;

  my $this = bless({
    @_
  }, $class);

  $this->{_session} = $session;

  my $request = Foswiki::Func::getRequestObject();
  my $refresh = $request->param("refresh") || '';
  $this->{_refresh} = ($refresh =~ /^(on|deepl|all)$/) ? 1:0;
  _writeDebug("refresh=".$this->{_refresh});

  return $this;
}

=begin TML

---++ ObjectMethod DESTROY()

makes sure all sub-objects are deconstructed as well

=cut

sub DESTROY {
  my $this = shift;

  undef $this->{_ua};
  undef $this->{_cache};
  undef $this->{_refresh};
  undef $this->{_json};
  undef $this->{_session};
}

=begin TML

---++ ObjectMethod DEEPL($params, $topic, $web) -> $string

implements the %DEEPL macro

=cut

sub DEEPL {
  my ($this, $params, $topic, $web) = @_;

  _writeDebug("called DEEPL()");

  my $result = '';
  my $text = $params->{_DEFAULT} // $params->{text} // '';
  return "" if $text eq "";

  try {
    $result = $this->translate($text, $params);
    #_writeDebug("result=".dump($result));
  } catch Error with {
    $result = shift;
    $result = _inlineError($result);
    _writeDebug("error: $result");
  };

  return $result;
}

=begin TML

---++ ObjectMethod DEEPL_LANGUAGES($params, $topic, $web) -> $string

implements the %DEEPL_LANGUAGES macro

=cut

sub DEEPL_LANGUAGES {
  my ($this, $params, $topic, $web) = @_;

  _writeDebug("called DEEPL_LANGUAGES()");

  my $result = "";
  my $sort = $params->{sort} // '';
  $sort = 'name' unless $sort =~ /^(language|name|code)$/;
  $sort = 'language' if $sort eq 'code';

  try {
    my $languages = $this->languages($params->{type});
    my @result = ();

    foreach my $lang (sort {$a->{$sort} cmp $b->{$sort}} @$languages) {
      my $line = $params->{format} // '$language';
      $line =~ s/\$(name|langname)\b/$lang->{name}/g;
      $line =~ s/\$(code|langtag)\b/$lang->{language}/g;
      push @result, $line;
    }
    if (@result) {
      $result = Foswiki::Func::decodeFormatTokens(($params->{header} // '') . join($params->{separator} // ", ", @result) . ($params->{footer} // ''));
    }
  } catch Error with {
    $result = shift;
    $result = _inlineError($result);
    _writeDebug("error: $result");
  };

  return $result;
}

=begin TML

---++ ObjectMethod jsonRpcTranslate($session, $request)

JSON-RPC implementation of the =translate= endpoint

=cut

sub jsonRpcTranslate {
  my ($this, $session, $request) = @_;

  my $wikiName = Foswiki::Func::getWikiName();
  my $web = $request->param("web") || $this->{session}{webName};
  my $topic = $request->param("topic") || $this->{session}{topicName};

  my $result = '';
  my $error;
  my %params = ();

  foreach my $key (DEEPL_PARAMS) {
    my $val = $request->param($key);
    next unless defined $val;
    $params{$key} = $val;
  }
 
  throw Error::Simple("no text parameter") unless defined $params{text};
  throw Error::Simple("empty text parameter") if $params{text} eq "";

  try {
    $result = $this->translate(undef, \%params);
  } catch Error with {
    $error = shift;
    $error =~ s/ at .*$//g;
    $error =~ s/\s+$//g;
    $error =~ s/^\s+//g;
  };

  throw Error::Simple($error) if $error;

  return $result;
}

=begin TML

---++ ObjectMethod handleDeeplSection()

takes care of content passed down from =%STARTDEPPL= ... =%ENDDEEPL= section.

=cut

sub handleDeeplSection {
  my ($this, $attrs, $text, $web, $topic) = @_;

  my %params = Foswiki::Func::extractParameters($attrs);

  _writeDebug("handleDeeplSection()");
  #_writeDebug("text=$text");

  my $result = "";
  try {
    $result = $this->translate($text, \%params);
  } catch Error with {
    $result = shift;
    $result = _inlineError($result);
    _writeDebug("error: $result");
  };

  return $result;
}

=begin TML

---++ ObjectMethod translate($text, $params) -> $result

Perl api to translate a text using deepl. =The $params= has may contain
the following keys:

   * text (used when =$tet= isn't defined)
   * source_lang
   * target_lang
   * context
   * split_sentences 
   * preserve_formatting 
   * formality 
   * glossary_id
   * tag_handling
   * outline_detection
   * non_splitting_tags
   * splitting_tags
   * ignore_tags

See https://www.deepl.com/de/docs-api/translate-text/translate-text for more information
on the request parameters.

=cut

sub translate {
  my ($this, $text, $params) = @_;

  $text //= $params->{text};
  
  my $userLang = $this->userLanguage();
  my $sourceLang = _mapLang($params->{source_lang});# // $userLang;
  my $targetLang = _mapLang($params->{target_lang}) // $userLang;

  if ($sourceLang && $targetLang eq $sourceLang) {
    _writeDebug("no translation required");
    return $text;
  }

  $params->{target_lang} = $targetLang;

  my $url = $Foswiki::cfg{DeeplPlugin}{APIUrl} || 'https://api-free.deepl.com/v2';
  $url =~ s/\/+$//;
  $url .= "/translate";

  _writeDebug("url=$url");

  my %form = ();
  foreach my $key (DEEPL_PARAMS) {
    my $val = $params->{$key};
    $form{$key} = $val if defined $val;
  }
  $form{text} = $text;

  my $key = $url . "::" . join("::", map {$_ . "=" . $form{$_}} sort keys %form);
  _writeDebug("key=$key");

  my $translation;
  $translation = $this->getCache->get($key) unless $this->{_refresh};

  if (defined $translation) {
    _writeDebug("found translation in cache");
    return $translation;
  }

  $form{auth_key} = $Foswiki::cfg{DeeplPlugin}{APIKey};

  my $response = $this->ua->post($url, 
    "Content-Type" => "application/x-www-form-urlencoded",
    Content => \%form
  );

  my $content = Encode::decode_utf8($response->content()); # SMELL: manual decoding as there is no content-encoding in response. 
  #_writeDebug("content=$content");

  throw Error::Simple($content) if $response->is_error;

  $content = $this->json->decode($content);
  $translation = $content->{translations}[0]{text};
  $this->getCache->set($key, $translation);

  return $translation;
}

=begin TML

---++ ObjectMethod translateTopic($meta, $sourceLang, $targetLang, $fields) -> $changed

Translates a topic from a source to a target language. The =$fields= parameter holds
a list of names of meta data to be translated. These are either formfield names or
"text" and "attachments". If "attachments" are listed in =$fields= will all comments
of all attachments be translated.

Information is read from =$meta= and stored back into =$meta=.

A boolean value =$changed= will be returned when a field has been translated successfully.

=cut

sub translateTopic {
  my ($this, $meta, $sourceLang, $targetLang, $fields) = @_;

  return unless $targetLang;
  my @fields = ();

  _writeDebug("called translateTopic()");

  if ($fields) {
    @fields = split(/\s*,\s*/, $fields);
  } else {
    push @fields, "text";
  }

  _writeDebug("sourceLang=$sourceLang, targetLang=$targetLang");
  my $changed = 0;
  foreach my $key (@fields) {
    _writeDebug("translating $key");

    if ($key eq 'text') {

      my $text = $meta->text();
      my $translation = $this->translate($text, {
        "source_lang" => $sourceLang,
        "target_lang" => $targetLang,
        "tag_handling" => "html",
        "ignore_tags" => "img",
      });
      next if $text eq $translation;

      $meta->text($translation);
      $changed = 1;
      
      next;
    } 

    # SMELL: does not work as part of a save handler
    if ($key eq 'attachments') {
      foreach my $attachment ($meta->find("FILEATTACHMENT")) {
        my $text = $attachment->{comment};
        next unless defined $text && $text ne "";
        my $translation = $this->translate($text, {
          "source_lang" => $sourceLang,
          "target_lang" => $targetLang,
          "tag_handling" => "html",
          "ignore_tags" => "img",
        });
        next if $text eq $translation;

        $attachment->{comment} = $translation;
        $changed = 1;
      }
      next;
    }

    my $field = $meta->get('FIELD', $key);
    next unless $field;
    my $text = $field->{value};

    my $translation = $this->translate($text, {
      "source_lang" => $sourceLang,
      "target_lang" => $targetLang,
      "tag_handling" => "html",
      "ignore_tags" => "img",
    });
    next if $text eq $translation;

    $field->{value} = $translation;
    $changed = 1;
  }

  return $changed;
}

=begin TML

---++ ObjectMethod userLanguage() -> $langTag

returns the language of the current user session

=cut

sub userLanguage {
  my $this = shift;

  return _mapLang($this->{_session}->i18n->language());
}

=begin TML

---++ ObjectMethod languages($type) -> $list

returns a list of languages supported by deepl. The =$type= 
parameter specifies whether =source= or =target= languages are 
requested, defaulting to =source=. Note that available source and
target languages might not be the same.

=cut

sub languages {
  my ($this, $type) = @_;

  $type //= 'source';

  my $key = "languages::".$type;
  my $content;
  $content = $this->getCache->get($key) unless $this->{_refresh};

  unless (defined $content) {
    my $url = $Foswiki::cfg{DeeplPlugin}{APIUrl} || 'https://api-free.deepl.com/v2';
    $url =~ s/\/+$//;
    $url .= "/languages?auth_key=" . $Foswiki::cfg{DeeplPlugin}{APIKey};
    $url .= "&type$type";

    my $response = $this->ua->get($url);
    throw Error::Simple($response->status_line) if $response->is_error;

    $content = Encode::decode_utf8($response->content()); # SMELL: manual decoding as there is no content-encoding in response. 
    $this->getCache->set($key, $content);
  } else {
    _writeDebug("found in cache");
  }

  my $languages = $this->json->decode($content);
  # lowercase
  foreach my $entry (@{$languages}) {
    $entry->{language} = _mapLang($entry->{language});
    _writeDebug("language=$entry->{language}, name=$entry->{name}");
  }

  return $languages;
}

=begin TML

---++ ObjectMethod json() -> $json

returns a JSON singleton object for all things json

=cut

sub json {
  my $this = shift;

  $this->{_json} //= JSON->new->allow_nonref;
  return $this->{_json};
}

=begin TML

---++ ObjectMethod ua() -> $ua

returns a LWP::UserAgent singleton object 

=cut

sub ua {
  my $this = shift;

  unless (defined $this->{_ua}) {
    $this->{_ua} //= LWP::UserAgent->new(
      # see https://www.whatismybrowser.com/guides/the-latest-user-agent/chrome
      agent => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      protocols_allowed => ['http', 'https'],
      timeout => 10
    );

    #$this->{_ua}->ssl_opts(verify_hostname => 0);

    my $proxy = $Foswiki::cfg{PROXY}{HOST};
    if ($proxy) {
      $this->{_ua}->proxy(['http', 'https'], $proxy);

      my $noProxy = $Foswiki::cfg{PROXY}{NoProxy};
      if ($noProxy) {
        my @noProxy = split(/\s*,\s*/, $noProxy);
        $this->{_ua}->no_proxy(@noProxy);
      }
    }
  }

  return $this->{_ua};
}

=begin TML

---++ ObjectMethod getCache() -> $cache

returns a Foswiki::Contrib::CacheContrib cache object

=cut

sub getCache {
  my $this = shift;

  $this->{_cache} //= Foswiki::Contrib::CacheContrib::getCache("deepl");
  return $this->{_cache};
}

# statics
sub _urlEncode {
  my $text = shift;

  return "" unless defined $text;

  $text =~ s{([^0-9a-zA-Z-_.:~!*/])}{sprintf('%%%02x',ord($1))}ge;

  return $text;
}

sub _mapLang {
  my $lang = shift;

  return unless $lang;
  $lang = lc($lang);

  return $LANGUAGE_MAPPING{$lang} // $lang;
}

sub _inlineError {
  my $msg = shift;

  $msg =~ s/ at .*$//g;# unless Foswiki::Func::isAnAdmin();
  $msg =~ s/\s+$//g;
  $msg =~ s/^\s+//g;
  return "<span class='foswikiAlert'>".$msg.'</span>';
}

sub _writeDebug {
  return unless TRACE;
  #Foswiki::Func::writeDebug("DeeplPlugin::Core - $_[0]");
  print STDERR "DeeplPlugin::Core - $_[0]\n";
}

1;
