# Original Author, more credit be to him
#%IRSSI = (
#	authors     => 'Wouter Coekaerts',
#	contact     => 'coekie@irssi.org',
#	license     => 'GPLv2',
#	url         => 'http://wouter.coekaerts.be/irssi',
#	changed     => '29/06/2004'
#);


# TODO
# Right so I knocked off the old todo list.
# Now, some umode checking would be nice :)
# Fix all the commands that only kinda work
# Sort out the messagelevel stuff
# Add badnicks, which are nicks we never wnt to talk to,
#  - Should invalidate a chan even if no goodnicks

# Add fingerprint support
# Hook to catch a fingerprint response on supported servers

use Irssi;
use strict;
use IO::Handle; # for (auto)flush
use Fcntl; # for sysopen
use vars qw($VERSION %IRSSI);
$VERSION = '0.0.' . (split(/ /, '$Rev: 1117 $'))[1];
my $LastModifiedDate = (split(/ /, '$LastChangedDate: 2010-12-15 11:26:10 +1100 (Wed, 15 Dec 2010) $'))[1];
$LastModifiedDate =~ s/([0-9]{4})-([0-9]{2})-([0-9]{2})/\3\/\2\/\1/;

%IRSSI = (
	authors     => 'richo, Wouter Coekaerts',
	contact     => 'richo@psych0tik.net',
	name        => 'goodnicks',
	description => 'alert you when nicks you don\'t trust are present in a channel',
	license     => 'GPLv2',
	url         => 'http://natalya.psych0tik.net/~richo/irssi/',
	changed     => $LastModifiedDate
);

sub cmd_help {
	print ( <<EOF
goodnicks is a system for keeping track of whether there's anyone who can hear you, who shouldn't.

GOODNICKS ADD nick          - Add nick to the goodnicks list for current channel
GOODNICKS DEL nick          - Delete nick from the goodnicks list for current channel
GOODNICKS CLEAR             - Clear the goodnicks list for current channel
GOODNICKS THEME COOL theme  - set the theme for when things are cool to theme
GOODNICKS THEME BAD theme   - set the theme to use when someone can hear you
GOODNICKS LIST              - Show the goodnicks list for the current channel
GOODNICKS WHO               - Show the list of people not valid to be on the current channel

EOF
    );
}

my $need_redraw = 0;                 # goodnicks needs redrawing
my $active_channel;                  # (REC)

my @goodnicks=();                     # array of hashes, containing the internal goodnicks of the active channel
my @badnicks=();
my @enabled_channels = ();
my @valid_peeps=();                     # all peeps who are allowed to be in the chan
my @seen_chans = (); # All the channels we've looked at to date.
	# nick => realnick
	# mode =>
	my ($MODE_OP, $MODE_HALFOP, $MODE_VOICE, $MODE_NORMAL) = (0,1,2,3);
	# status =>
	my ($STATUS_NORMAL, $STATUS_JOINING, $STATUS_PARTING, $STATUS_QUITING, $STATUS_KICKED, $STATUS_SPLIT) = (0,1,2,3,4,5);
	# text => text to be printed
	# cmp => text used to compare (sort) nicks


# 'cached' settings
my ($screen_prefix, $irssi_width, @prefix_mode, @prefix_status, $height, $goodnicks_width);


sub update {
	read_settings();
    # check_status();
}

##################
##### OUTPUT #####
##################

### off ###

sub cmd_off {
		fifo_stop();
}

### fifo ###

sub cmd_on {
    # Stub
}


sub cmd_theme {
    my @args = split(/ /, shift);
    if (@args < 2 and (@args[0] == 'cool' or @args[0] == 'bad')) {
        Irssi::print("Usage: goodnicks theme [cool | bad] [themename]");
    } else {
        Irssi::settings_set_str('goodnicks_theme_'.@args[0], @args[1]);
    }
}

sub cmd_debug {
    Irssi::print("Current Server: ".Irssi::active_server()->{tag});
    Irssi::print("Alt form ". Irssi::active_server()->{tag});
    #Irssi::print(@valid_peeps);
    #my $tmpnix = Irssi::settings_get_str('goodnicks_chan_'.$channel.'valid_peeps');
    #Irssi::settings_add_str('goodnicks', 'goodnicks_chan_kthxbai_valid_peeps', '');
    #Irssi::print(Irssi::settings_get_str('goodnicks_'.Irssi::active_server()->{tag}.'_kthxbai_valid_peeps'));
}

### both ###

sub goodnicks_write_start {
    # Write out status line
}

sub goodnicks_write_end {
    # Dummy, do nothing
}

sub goodnicks_write_line {
    #dummy
}

# redraw (with little delay to avoid redrawing to much)
sub need_redraw {
    # Code to validate @goodnicks against @valid_peeps needs to go in here.
    my $func = \&chan_is_cool;
    # If valid peeps is empty we assume that we don't care who's in there.
    if (@valid_peeps > 0) {
        foreach my $nick (@goodnicks){
            if (not(grep m/^\Q$nick\E$/i, @valid_peeps)) {
                push @badnicks, $nick;
                $func = \&chan_is_bad;
            }
        }
    }
    &$func()

}

sub haxy_print_hook {
    Irssi::signal_stop();
}
sub set_theme {
    my $theme = shift;
    Irssi::signal_add_first('print text', 'haxy_print_hook');
    Irssi::command("set theme ".$theme);
    Irssi::signal_remove('print text', 'haxy_print_hook');
}


sub chan_is_cool {
    # Do stuff to alert user chan is well groovy
    my $theme = Irssi::settings_get_str('goodnicks_theme_cool');
    set_theme($theme)
}

sub chan_is_bad {
    # Do stuff to alert user to chan not being all good
    my $theme = Irssi::settings_get_str('goodnicks_theme_bad');
    set_theme($theme)
}


sub redraw {
    #stub
} 


# redraw (with delay) if the window is visible (only in screen mode)
sub sig_gui_print_text_finished {
	if ($need_redraw) { # there's already a redraw 'queued'
		return;
	}
	my $window = @_[0];
	if ($window->{'refnum'} == Irssi::active_win->{'refnum'} || Irssi::settings_get_str('goodnicks_screen_split_windows') eq '*') {
		need_redraw;
		return;
	}
	foreach my $win (split(/[ ,]/, Irssi::settings_get_str('goodnicks_screen_split_windows'))) {
		if ($window->{'refnum'} == $win || $window->{'name'} eq $win) {
			need_redraw;
			return;
		}
	}
}

####################
##### NICKLIST #####
####################


sub get_valid_peeps {
    my $channel = shift;
    $channel = $channel->{name};
    $channel =~ s/^#//;
    if (not ( grep m/^\Q$channel\E$/i, @seen_chans)) {
        Irssi::settings_add_str('goodnicks', 'goodnicks_'.Irssi::active_server()->{tag}.'_'.$channel.'_valid_peeps', '');
    }
    my $thisnick;
    my $tmpnix = Irssi::settings_get_str('goodnicks_'.Irssi::active_server()->{tag}.'_'.$channel.'_valid_peeps');
    $tmpnix =~ s/\\e/\033/g;
    @valid_peeps = split( /,/, $tmpnix);
}


# make the (internal) goodnicks (@goodnicks)
sub make_goodnicks {
    my $thisnick;

    @valid_peeps = ();
	@goodnicks = ();
    @badnicks = ();

	### get & check channel ###
	my $channel = Irssi::active_win->{active};

	if (!$channel || (ref($channel) ne 'Irssi::Irc::Channel' && ref($channel) ne 'Irssi::Silc::Channel') || $channel->{'type'} ne 'CHANNEL' || ($channel->{chat_type} ne 'SILC' && !$channel->{'names_got'}) ) {
		$active_channel = undef;
		# no goodnicks
	} else {
		$active_channel = $channel;
		### make goodnicks ###
        get_valid_peeps($active_channel);
		foreach my $nick ($channel->nicks()) {
			$thisnick = {'nick' => $nick->{'nick'}};
            if (grep m/^.+$/, $thisnick) {
                push @goodnicks, $thisnick->{nick};
            }
		}

	}
	need_redraw();
}

# insert nick(as hash) into goodnicks
# pre: cmp has to be calculated

# scroll the goodnicks, arg = number of lines to scroll, positive = down, negative = up

sub is_active_channel {
	my ($server,$channel) = @_; # (channel as string)
	return ($server && $server->{'tag'} eq $active_channel->{'server'}->{'tag'} && $server->channel_find($channel) && $active_channel && $server->channel_find($channel)->{'name'} eq $active_channel->{'name'});
}

sub sig_join {
    make_goodnicks();
}

sub sig_kick {
    make_goodnicks();
}

sub sig_part {
    make_goodnicks();

}

sub sig_quit {
    make_goodnicks();
}

sub sig_nick {
    make_goodnicks();
}

sub cmd_add {
    my $nick = shift;
    if (not ( grep m/^\Q$nick\E$/i, @valid_peeps)) {
        my $channel = $active_channel->{name};
        $channel =~ s/^#//;
        push @valid_peeps, $nick;
        my $tmpnicks = join(',', @valid_peeps);
        Irssi::settings_set_str('goodnicks_'.Irssi::active_server()->{tag}.'_'.$channel.'_valid_peeps', $tmpnicks);
        write_to_current_channel("Added ".$nick." to goodnicks");
    } else {
        write_to_current_channel($nick." already present in goodnicks");
    }
    make_goodnicks();
}

sub cmd_del {
    my $nick = shift;
    my @delorted = ();
    my $index = 0;
    my $channel = $active_channel->{name};
    $channel =~ s/^#//;
    my @newnicks = ();
    while ($index <= $#valid_peeps) {
        if (lc($valid_peeps[$index]) ne lc($nick)) {
            push @newnicks, $valid_peeps[$index];
            push @delorted, $nick;
        }
        $index++;
    }
    @valid_peeps = @newnicks;
    my $tmpnicks = join(',', @valid_peeps);
    Irssi::settings_set_str('goodnicks_'.Irssi::active_server()->{tag}.'_'.$channel.'_valid_peeps', $tmpnicks);
    if (@delorted > 0) {
        my $data = join(', ', @delorted);
        write_to_current_channel("Deleted from goodnicks: ".$data);
    } else {
        write_to_current_channel($nick." not found in goodnicks.");
    }
    make_goodnicks();
}

sub cmd_clear {
    my $channel = $active_channel->{name};
    $channel =~ s/^#//;
    @valid_peeps = ();
    my $tmpnicks = '';
    Irssi::settings_set_str('goodnicks_'.Irssi::active_server()->{tag}.'_'.$channel.'_valid_peeps', $tmpnicks);
    write_to_current_channel("Cleared goodnicks for ".$active_channel->{name});
    make_goodnicks();
}

sub write_to_current_channel {
    my $data = shift;
    $active_channel->print($data, MSGLEVEL_CRAP);
}

sub cmd_list {
    if (@valid_peeps > 0) {
        my $nicks;
        write_to_current_channel("Valid peeps for ".$active_channel->{name});
        $nicks = join(', ', @valid_peeps);
        write_to_current_channel($nicks);
    } else {
        write_to_current_channel("goodnicks disabled for ".$active_channel->{name});
    }
}
sub cmd_who {
    if (@badnicks > 0) {
        my $nicks;
        write_to_current_channel("Invalid peeps on ".$active_channel->{name});
        $nicks = join(', ', @badnicks);
        write_to_current_channel($nicks);
    } else {
        if (@valid_peeps > 0) {
            write_to_current_channel("No invalid peeps on ".$active_channel->{name});
        } else {
            write_to_current_channel("goodnicks disabled for ".$active_channel->{name});
        }
    }
}

##### command binds #####
Irssi::command_bind 'goodnicks' => sub {
    my ( $data, $server, $item ) = @_;
    $data =~ s/\s+$//g;
    Irssi::command_runsub ('goodnicks', $data, $server, $item ) ;
};
Irssi::signal_add_first 'default command goodnicks' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};
Irssi::command_bind('goodnicks help',\&cmd_help);
Irssi::command_bind('goodnicks on',\&cmd_on);
Irssi::command_bind('goodnicks add', \&cmd_add);
Irssi::command_bind('goodnicks del', \&cmd_del);
Irssi::command_bind('goodnicks clear', \&cmd_clear);
Irssi::command_bind('goodnicks theme', \&cmd_theme);
# XXX Need to add this.
Irssi::command_bind('goodnicks list', \&cmd_list);
Irssi::command_bind('goodnicks who', \&cmd_who);
Irssi::command_bind('goodnicks off',\&cmd_off);
Irssi::command_bind('goodnicks debug',\&cmd_debug);

#
###### signals #####
Irssi::signal_add_last('window item changed', \&make_goodnicks);
Irssi::signal_add_last('window changed', \&make_goodnicks);
#Irssi::signal_add_last('channel wholist', \&sig_channel_wholist);
Irssi::signal_add_first('message join', \&sig_join); # first, to be before ignores
Irssi::signal_add_first('message part', \&sig_part);
Irssi::signal_add_first('message kick', \&sig_kick);
Irssi::signal_add_first('message quit', \&sig_quit);
Irssi::signal_add_first('message nick', \&sig_nick);
#Irssi::signal_add_first('message own_nick', \&sig_nick);
#Irssi::signal_add_first('nick mode changed', \&sig_mode);
#
#Irssi::signal_add('setup changed', \&read_settings);
#
###### settings #####
#Irssi::settings_add_str('goodnicks', 'goodnicks_screen_prefix', '\e[m ');
Irssi::settings_add_str('goodnicks', 'goodnicks_prefix_mode_op', '\e[32m@\e[39m');
Irssi::settings_add_str('goodnicks', 'goodnicks_prefix_mode_halfop', '\e[34m%\e[39m');
Irssi::settings_add_str('goodnicks', 'goodnicks_prefix_mode_voice', '\e[33m+\e[39m');
Irssi::settings_add_str('goodnicks', 'goodnicks_prefix_mode_normal', ' ');
Irssi::settings_add_str('goodnicks', 'goodnicks_theme_bad', 'intruder');
Irssi::settings_add_str('goodnicks', 'goodnicks_theme_cool', 'default');
#
#Irssi::settings_add_int('goodnicks', 'goodnicks_width',11);
#Irssi::settings_add_int('goodnicks', 'goodnicks_height',24);
Irssi::settings_add_str('goodnicks', 'goodnicks_channels', '');
#Irssi::settings_add_str('goodnicks', 'goodnicks_screen_split_windows', '');
#Irssi::settings_add_str('goodnicks', 'goodnicks_automode', '');
Irssi::settings_add_str('goodnicks', 'goodnicks_', '');
#
#}
