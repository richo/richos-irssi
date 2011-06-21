$VERSION = "0.1";
%IRSSI = (
    authors     => "Jari Matilainen",
    contact     => "vague@vague.se",
    name        => "timezones",
    description => "timezones displayer",
    license     => "Public Domain",
    url         => "http://vague.se"
);

use Irssi::TextUI;

my $result;
my $refresh_tag;

sub timezones {
  my ($item,$get_size_only) = @_;
  my ($datetime) = Irssi::settings_get_str("timezones_clock_format");
  my ($div) = Irssi::settings_get_str("timezones_divider");
  my (@timezones) = split / /, Irssi::settings_get_str("timezones");
  my (@zi); # Zoneinfo

  my $result = "";

  foreach(@timezones) {
    @zi = split /:/, $_;
    if(length($result)) { $result .= $div; }
    my $res = "";
    chomp($res = `TZ='$zi[1]' date +$datetime`);
    $result .= $zi[0] . ": " . $res;
  }

  $item->default_handler($get_size_only, undef, $result, 1);
}

sub refresh_timezones {
  Irssi::statusbar_items_redraw('timezones');
}

sub init_timezones {
  Irssi::timeout_remove($refresh_tag) if ($refresh_tag);
  $refresh_tag = Irssi::timeout_add(30000, 'refresh_timezones', undef);
}

Irssi::statusbar_item_register('timezones', '{sb_l $0-}', 'timezones');
Irssi::settings_add_str('timezones', 'timezones_clock_format', '%H:%M:%S');
Irssi::settings_add_str('timezones', 'timezones_divider', ' ');
Irssi::settings_add_str('timezones', 'timezones', 'GMT EST');

init_timezones();
Irssi::signal_add('setup changed','init_timezones');
#Irssi::command("statusbar sb_timezones enable");
#Irssi::command("statusbar sb_timezones add -alignment left barstart");
#Irssi::command("statusbar sb_timezones add -after barstart timezones");
#Irssi::command("statusbar sb_timezones add -alignment right barend");
refresh_timezones();
