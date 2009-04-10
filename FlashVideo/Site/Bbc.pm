# Part of get-flash-videos. See get_flash_videos for copyright.
package FlashVideo::Site::Bbc;

use strict;
use FlashVideo::Utils;

sub find_video {
  my ($self, $browser, $page_url) = @_;

  my $has_xml_simple = eval { require XML::Simple };
  if(!$has_xml_simple) {
    die "Must have XML::Simple installed to download BBC videos";
  }

  # Get playlist XML
  my $playlist_xml;
  if ($browser->content =~ /<param name="playlist" value="(http:.+?\.xml)"/) {
    $playlist_xml = $1;
  }
  elsif($browser->content =~ /empDivReady\s*\(([^)]+)/) {
    my @params = split /,\s*/, $1;

    my $id   = $params[3];
    my $path = $params[4];

    $id   =~ s/['"]//g;
    $path =~ s/['"]//g;

    $playlist_xml = URI->new_abs($path, $browser->uri) . "/media/emp/playlists/$id.xml";
  }
  elsif($browser->uri =~ m!/(b[0-9a-z]{7})(?:/|$)!) {
    # Looks like a pid..
    my @gi_cmd = (qw(get_iplayer -g --pid), $1);
    print STDERR "get_flash_videos does not support iplayer, but get_iplayer does..\n";
    print STDERR "Attempting to run '@gi_cmd'\n";
    exec @gi_cmd;
    # Probably not installed..
    print STDERR "Please download get_iplayer from http://linuxcentre.net/getiplayer/\n";
    print STDERR "and install in your PATH\n";
    exit 1;
  }
  else {
    die "Couldn't find BBC XML playlist URL in " . $browser->uri->as_string;
  }

  $browser->get($playlist_xml);
  if (!$browser->success) {
    die "Couldn't download BBC XML playlist $playlist_xml: " .
      $browser->response->status_line;
  }

  my $playlist = eval {
    XML::Simple::XMLin($browser->content)
  };

  if ($@) {
    die "Couldn't parse BBC XML playlist: $@";
  }

  my $sound = ($playlist->{item}->{guidance} !~ /has no sound/);
  my $info = $playlist->{item}->{media}->{connection};

  $info->{application} ||= "ondemand";

  my $data = {
    app      => $info->{application},
    tcUrl    => "rtmp://$info->{server}/$info->{application}",
    swfUrl   => "http://www.bbc.co.uk/player/emp/2.10.7938_7967/9player.swf",
    pageUrl  => $page_url,
    rtmp     => "rtmp://" .  $info->{server} . "/$info->{application}",
    playpath => $info->{identifier},
    flv      => title_to_filename('BBC - ' . $playlist->{title} .
                                ($sound ? '' : ' (no sound)'))
  };

  # 'Secure' items need to be handled differently - have to get a token to
  # pass to the rtmp server.
  if ($info->{identifier} =~ /^secure/) {
    my $url = "http://www.bbc.co.uk/mediaselector/4/gtis?server=$info->{server}" .
              "&identifier=$info->{identifier}&kind=$info->{kind}" .
              "&application=$info->{application}&cb=123";

    print STDERR "Got BBC auth URL for 'secure' video: $url\n";

    $browser->get($url);

    # BBC redirects us to the original URL which is odd, but oh well.
    if (my $redirect = $browser->response->header('Location')) {
      print STDERR "BBC auth URL redirects to: $url\n";
      $browser->get($redirect);
    }

    my $stream_auth = eval {
      XML::Simple::XMLin($browser->content);
    };

    if ($@) {
      die "Couldn't parse BBC stream auth XML for 'secure' stream.\n" .
          "XML is apparently:\n" .
          $browser->content() . "\n" .
          "XML::Simple said: $@";
    }

    my $token = $stream_auth->{token};

    if (!$token) {
      die "Couldn't get token for 'secure' video download";
    }

    $data->{app} = "ondemand?_fcs_vhost=$info->{server}"
            . "&auth=$token"
            . "&aifp=v001&slist=" . $info->{identifier};
    $data->{tcUrl} = "rtmp://$info->{server}/ondemand?_fcs_vhost=$info->{server}"
            . "&auth=$token"
            . "&aifp=v001&slist=" . $info->{identifier};
  }

  return $data;
}

1;
