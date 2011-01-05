package Progress::Indicator;
use strict;
use Time::HiRes;
use POSIX qw(strftime);

use vars qw'%indicator $VERSION';
$VERSION = '0.02';

=head1 NAME

Progress::Indicator - yet another progress indicator

=head1 SYNOPSIS
  use Progress::Indicator 'progress';

  while (<$fh>) {
      progress $fh, "Working on list";
  }

  for (@list) {
      progress \@list, "Working on list";
  }

=cut

sub handle_unsized {
    my ($i) = @_;
    my $now = time();
    if (my $u = $i->{per_item}) {
	    $u->($i);
    };
    if ($i->{last} + $i->{interval} <= $now ) {
        local $|;
        $| = 1;
        $i->{position} = $i->{get_position}->($i);
        my $elapsed = $now - $i->{start};
        my $elapsed_str = strftime '%H:%M:%S', gmtime($elapsed);
        my $per_sec = $i->{position} / $elapsed; # /
        my $line = sprintf "%s\t(%d)\tElapsed: %s\t%0.2f/s",
            $i->{info},
            $i->{position},
            $elapsed_str,
            $per_sec
        ;
        my $lastline = $i->{lastline};
        $i->{lastline} = $line;
        while (length $line < length($lastline)) {
	        $line .= " ";
        }
        print STDERR "$line\r";
        $i->{last} = $now;
    }
}

sub handle_sized {
    my ($i) = @_;
    my $now = time();
    if (my $u = $i->{per_item}) {
	    $u->($i);
    };
    if ($i->{last} + $i->{interval} <= $now ) {
        local $|;
        $| = 1;
        $i->{position} = $i->{get_position}->($i);
        my $perc = $i->{position} / $i->{total}; # /
        my $elapsed = $now - $i->{start};
        my $per_sec = $i->{position} / $elapsed; # /
        my $remaining = int (($i->{total} - $i->{position}) / $per_sec);
        if ($remaining < 0) {
            $remaining = 1;
        };
        #warn "gmt:$_<\n" for gmtime($remaining);
        my $eta = strftime '%H:%M:%S', localtime(time + $remaining);
        #$remaining = strftime '%H:%M:%S', gmtime($remaining);
        my $line = sprintf "%s %3d%% ETA: %s %8.2f/s (%d of %d)",
            $i->{info},
            $perc * 100,
            $eta,
            $per_sec,
            $i->{position},
            $i->{total},
            ;
        $line = substr $line, 0, 79 if length $line >= 80;
        my $lastline = $i->{lastline};
        $i->{lastline} = $line;
        while (length $line < length($lastline)) {
 	        $line .= " ";
        }
        print STDERR "$line\r";
        $i->{last} = $now;
    }
}

sub new_indicator {
    my ($item,$info,$options) = @_;
    $options ||= {};
    $options->{interval} ||= 10;
    my $now = time();

    my ($per_item,$position,$total,$handler,$get_position);

    $handler = $options->{type} || undef;

    if (ref $item eq 'ARRAY') {
        $handler ||= 'array';
    } elsif (ref $item eq 'GLOB' or ref $item eq 'IO::Handle') {
        $position = tell $item;
        if ($position < 0 or ! -s $item) {
	        $handler ||= 'unsized';
	    } else {
	        $handler ||= 'sized';
	    };
    } else {
        $handler ||= 'unsized';
    };
    if ($handler eq 'array') {
        # An array which we can size
        $position = 0;
        $total = @$item;
        $per_item = sub { $_[0]->{position}++ };
        $get_position = sub { $_[0]->{position} };
    } elsif ($handler eq 'sized') {
        # A file which we can maybe size
        # Consider to discriminate between $. and tell()
        $position = exists $options->{position}
                  ? exists $options->{position}
                  : tell $item;
        $total = exists $options->{total}
               ? $options->{total}
               : -s $item;
        #warn "Item size for $item is $total";
        $per_item = exists $options->{per_item}
                  ? $options->{per_item}
                  : undef;
        $get_position = exists $options->{tell}
                      ? $options->{tell}
                      : sub { tell $item };
    } else { # item of unknown size, count iterations
        $per_item = sub { $_[0]->{position}++ };
        $total = undef;
        $position = 0;
        $get_position = sub { $_[0]->{position} };
    };
    #warn $handler;
    $handler = defined $total ? \&handle_sized : \&handle_unsized;

    $indicator{ $item } = {
        start    => $now,
        last     => $now,
        position => $position,
        total    => $total,
        info     => $info,
        lastline => '',
        handler  => $handler,
        per_item => $per_item,
        get_position => $get_position,
        %$options,
    };
}

sub progress {
    my ($item,$info,$options) = @_;

    # No output if we're not interactive
    my ($out) = select;
    return if (! -t $out);

    my $i = $indicator{ $item };
    goto &new_indicator
	    if (! defined $i);
    $i->{handler}->($i);
}

sub import {
    my ($this,$name) = @_;
    if (! defined $name) {
	    $name = 'progress';
    };
    my $target = caller();
    no strict 'refs';
    *{"$target\::$name"} = \&progress;
}

1;
