# $Id$
package Subtitles;
use strict;
require Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK @codecs $VERSION);
@ISA = qw(Exporter);
@EXPORT = qw(codecs time2str);
@EXPORT_OK = qw(codecs time2hms time2shms hms2time time2str);
$VERSION = '0.01';


push @codecs, map { "Subtitles::Codec::$_" } qw( srt sub sub2 smi);

#
# package-oriented API
#

sub time2hms
{
   shift if $#_ == 1; # package and object
   my $time = $_[0];
   $time = 0 if $time < 0;
   return int($time/3600),int(($time%3600)/60),int($time%60),int(($time-int($time))*1000 + .5),
}

sub time2shms
{
   shift if $#_ == 1; # package and object
   my $time = $_[0];
   my $sign;
   if ( $time < 0) {
      $sign = -1;
      $time = -$time;
   } else {
      $sign = 1;
   }
   return $sign,int($time/3600),int(($time%3600)/60),int($time%60),int(($time-int($time))*1000 + .5),
}

sub hms2time
{
   shift if $#_ == 4; # package and object
   my ( $h, $m, $s, $ms) = @_;
   return $h * 3600 + $m * 60 + $s + $ms / 1000;
}


sub time2str
{
   shift if $#_ == 1; # package and object
   my $time = $_[0];
   my $is_minus = '';
   $time = -$time, $is_minus = "-" if $time < 0;
   return sprintf ( "$is_minus%02d:%02d:%02d.%03d", time2hms($time));
}

sub codecs { @codecs }

#
# object-oriented API
#

sub new
{
   my $class = shift;
   return bless {
      codec  => undef,
      @_,
      text   => [],
      from   => [],
      to     => [],
      class  => $class,
   }, $class;
}

sub load
{
   my ( $self, $fh, $codec) = @_;
   $self-> clear;
   my @content;
   while (<$fh>) {
      chomp;
      s/[\s\n\r]+$//;
      push @content, $_;
   }
   unless ( defined $codec) {
      for ( @content) {
         my $line = $_;
	 for ( @codecs) {
            next unless $_-> match( $line);
	    $codec = $_;
	 }
      }
   }
   unless ( defined $codec) {
      $@ = "No suitable codec is found";
      return undef;
   }
   my $ret;
   eval {
      $ret = $codec-> read( $self, \@content);
   };
   return undef if $@ or !defined $ret;
   # validate
   if ( @{$self->{from}} == 0) {
      $@ = "Empty subtitle";
      return undef;
   }
   if ( @{$self->{from}} != @{$self->{to}}) {
      if ( @{$self->{from}} == @{$self->{to}} + 1) {
         push @{$self->{to}}, $self->{from}->[-1] + 2; # fix a dangling tail 
      } else {
         my $a = @{$self->{from}}; 
         my $b = @{$self->{to}}; 
         $@ = "Number of 'from' ($a) and 'to' ($b) timeframe positions is different";
         return undef;
      }
   }
   if ( @{$self->{from}} != @{$self->{text}}) {
      if ( @{$self->{from}} == @{$self->{text}} + 1) {
         push @{$self->{text}}, ''; # fix a dangling tail
      } else {
         my $a = @{$self->{from}}; 
         my $b = @{$self->{text}}; 
         $@ = "Number of timeframes ($a) is different from the number of text lines ($b)";
         return undef;
      }
   }
   $self->{codec} = $codec;
   return 1;
}

sub codec
{
   return $_[0]-> {codec} unless $#_;
   my ( $self, $codec) = @_;
   my %c = map { $_ => 1 } @codecs;
   return unless exists $c{$codec};
   return if defined $self->{codec} && $self->{codec} eq $codec;
   $self->{codec}-> downgrade($self, $codec) if defined $self->{codec};
   $self->{codec} = $codec;
}

sub rate
{
   return $_[0]-> {rate} unless $#_;
   return if defined $_[1] && $_[1] <= 0;
   $_[0]->{rate} = $_[1];
}

# parses 
#   SS
#   MM:SS
#   HH:MM:SS
#   HH:MM:SS,msec
#   MM:SS,msec
# into time
sub parse_time
{
   my ( $self, $time) = @_;
   my $sign = 1;
   $sign = -1 if $time =~ s/^-//;
   if ( $time =~ m/^(?:(\d{1,2}):)?(?:(\d{1,2}):)?(\d{1,2})(?:[\,\.\:](\d{1,3}))?$/) {
      my ( $h, $m, $s, $ms) = ( $1, $2, $3, $4);
      $h  = 0 unless defined $h;
      $m  = 0 unless defined $m;
      $ms = '0' unless defined $ms;
      $ms .= '0' while length($ms) < 3;
      return $sign * ( $h * 3600 + $m * 60 + $s + $ms / 1000);
   } elsif ( $self && $self-> {codec}) {
      my $t = $self->{codec}->time($time);
      return $sign * $t if defined $t;
   }
   undef;
}

sub shift { $_[0]-> transform( 1, $_[1]) }
sub scale { $_[0]-> transform( $_[1], 0) }

sub lines { scalar @{$_[0]->{text}} }

# applies linear (y = ax+b) transformation
sub transform
{
   my ( $self, $a, $b) = @_;
   return if $a == 1 && $b == 0;
   my $i;
   my $n = $self-> lines;
   my $from = $self->{from};
   my $to   = $self->{to};
   for ( $i = 0; $i < $n; $i++) {
      $$from[$i] = $a * $$from[$i] + $b;
      $$to[$i]   = $a * $$to[$i] + $b;
   }
}

sub dup
{
   my ( $self, $clear) = @_;
   if ( $clear) {
      return bless { 
	%$self,
	text => [],
	from => [],
	to   => [],
      }, $self-> {class};
   } else {
      return bless { 
	%$self,
	text => [ @{$self->{text}}],
	from => [ @{$self->{from}}],
	to   => [ @{$self->{to}}],
      }, $self-> {class};
   }
}

sub clear
{
   my $self = $_[0];
   $self-> {text} = [];
   $self-> {from} = [];
   $self-> {to}   = [];
}

sub join
{
   my ( $self, $guest, $time_between) = @_;
   $time_between = 2 unless defined $time_between;
   my $delta = $time_between + $self-> length;
   push @{$self->{text}}, @{$guest->{text}};
   push @{$self->{from}}, map { $_ + $delta } @{$guest->{from}};
   push @{$self->{to}},   map { $_ + $delta } @{$guest->{to}};
}

sub split
{
   my ( $self, $where) = @_;

   my ( $s1, $s2) = ( $self-> dup(1), $self-> dup(1));

   my $i;
   my $n = $self->lines;
   my $t = $self->{to};
   my ( $end, $begin);

   for ( $i = 0; $i < $n; $i++) {
      next if $$t[$i] < $where;
      $begin = $i;
      $end = $i - 1;
      last;
   }

   if ( defined $end && $end >= 0) {
      @{$s1->{text}} = @{$self->{text}}[0..$end];
      @{$s1->{from}} = @{$self->{from}}[0..$end];
      @{$s1->{to}}   = @{$self->{to}}[0..$end];
   }
   if ( defined $begin && $begin < $n) {
      @{$s2->{text}} = @{$self->{text}}[$begin..$n-1];
      @{$s2->{from}} = @{$self->{from}}[$begin..$n-1];
      @{$s2->{to}}   = @{$self->{to}}[$begin..$n-1];
      $s2-> shift( -$where);
   }
   ($s1,$s2);
}

sub length
{
   my $self = $_[0];
   return @{$self->{to}} ? $self->{to}->[-1] : 0;
}

sub save
{
   my ( $self, $fh) = @_;
   my $content;
   eval {
      $content = $self-> {codec}-> write( $self);
   };
   return 0 if $@ or ! defined $content;
   for ( @$content) {
      next if print $fh $_, "\n";
      $@ = "write error: $!";
      return 0;
   }
   1;
}

package Subtitles::Codec;
use vars qw(@ISA);

sub match 
{
   my ( $self, $line) = @_;
   undef;
}

sub read 
{
   my ( $self, $sub, $content) = @_;
   die "abstract method call";
}

sub write 
{
   my ( $self, $sub) = @_;
   die "abstract method call";
}

sub time { undef }

sub downgrade {}

package Subtitles::Codec::srt;
use vars qw(@ISA);
@ISA=qw(Subtitles::Codec);

sub match
{
   $_[1] =~ m/^(\d\d):(\d\d):(\d\d)\,(\d\d\d)\s*-->\s*(\d\d):(\d\d):(\d\d)\,(\d\d\d)/;
}

sub read
{
   my ( $self, $sub, $content) = @_;

   my $stage = 0;
   my $num = 1;
   my $line = 0;
# 0:   
# 1: 1
# 2: 00:00:04,073 --> 00:00:05,781
# 3: Subtitle

   for ( @$content) {
      $line++;
      if ( $stage == 0) {
         next unless length;
	 die "Invalid line numbering at line $line\n" unless m/^\d+$/;
	 $num++;
	 $stage++;
      } elsif ( $stage == 1) {
         die "Invalid timing at line $line\n" unless
            m/^(\d\d):(\d\d):(\d\d)\,(\d\d\d)\s*-->\s*(\d\d):(\d\d):(\d\d)\,(\d\d\d)/;
	 push @{$sub->{from}}, Subtitles::hms2time( $1, $2, $3, $4);
	 push @{$sub->{to}},   Subtitles::hms2time( $5, $6, $7, $8); 
	 $stage++;
      } elsif ( $stage == 2) {
         if ( length) {
	    push @{$sub->{text}}, $_;
	    $stage++;
	 } else {
	    push @{$sub->{text}}, '';
	    $stage = 0;
	 }
      } else {
         if ( length) {
	    $sub->{text}->[-1] .= "\n$_";
	 } else {
	    $stage = 0;
	 }
      }
   }
   1;
}

sub write
{
   my ( $self, $sub) = @_;

   my $n = @{$sub->{text}};
   my $i;
   my @ret;
   my $from = $sub->{from};
   my $to   = $sub->{to};
   my $text = $sub->{text};
   for ( $i = 0; $i < $n; $i++) {
      push @ret, 
         $i + 1,
         sprintf ( "%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d",
	    Subtitles::time2hms($from->[$i]),
	    Subtitles::time2hms($to->[$i]),
	 ),
	 split ("\n", $text->[$i]),
	 ''
      ;
   }
   \@ret;
}

package Subtitles::Codec::sub;
use vars qw(@ISA);
@ISA=qw(Subtitles::Codec);

sub match
{
   $_[1] =~ m/^{\d+}{\d+}/; 
}

sub read
{
   my ( $self, $sub, $content) = @_;

   my $line = 0;
# {3724}{3774}Text

   my $fps = $sub->{rate} ? $sub->{rate} : 25;
   my $from = $sub->{from};
   my $to   = $sub->{to};
   my $text = $sub->{text};

   for ( @$content) {
      $line++;
      m/^{(\d+)}{(\d+)}(.*)$/ or die "Invalid input at line $line\n";
      push @$from, $1/$fps;
      push @$to,   $2/$fps;
      my $t = $3;
      $t=~ s/\|\s*/\n/g;
      push @$text, $t;
   }
   1;
}

sub write
{
   my ( $self, $sub) = @_;
   
   my $fps = $sub->{rate} ? $sub->{rate} : 25;

   my $n = @{$sub->{text}};
   my $i;
   my @ret;
   my $from = $sub->{from};
   my $to   = $sub->{to};
   my $text = $sub->{text};
   for ( $i = 0; $i < $n; $i++) {
      my $t = $text->[$i];
      $t =~ s/\n/\|/g;
      push @ret, 
         sprintf ( "{%d}{%d}%s",
	    int( $from->[$i] * $fps + .5),
	    int( $to->[$i]   * $fps + .5),
	    $t
	 );
   }
   \@ret;
}

package Subtitles::Codec::sub2;
use vars qw(@ISA);
@ISA=qw(Subtitles::Codec);

sub match
{
   $_[1] =~ m/^\[(SUBTITLE|COLF)\]/i; 
}

sub read
{
   my ( $self, $sub, $content) = @_;

   my $line = 0;
# [INFORMATION]
# [AUTHOR]
# [SOURCE]
# [PRG]
# [FILEPATH]
# [DELAY]
# [CD TRACK]
# [COMMENT]
# [END INFORMATION]
# 
# [SUBTITLE]
# [COLF]&HFFFFFF,[STYLE]no,[SIZE]18,[FONT]Arial
# 00:04:10.26,00:04:13.57
# Welcome to Gattaca.

   my $from = $sub->{from};
   my $to   = $sub->{to};
   my $text = $sub->{text};
   my @header;

   my $read_header = 1;
   my $state = 0;

   for ( @$content) {
      $line++;
      if ( $read_header) {
         if ( m/^(\d\d):(\d\d):(\d\d)\.(\d\d)\,(\d\d):(\d\d):(\d\d)\.(\d\d)/) {
	    $read_header = 0;
	    goto BODY;
	 }
         push @header, $_;
      } else {
      BODY:
         if ( $state == 0) {
	    next unless length;
            die "Invalid timing at line $line\n" unless
               m/^(\d\d):(\d\d):(\d\d)\.(\d\d)\,(\d\d):(\d\d):(\d\d)\.(\d\d)/;
	    push @$from, Subtitles::hms2time( $1, $2, $3, $4 * 10);
	    push @$to,   Subtitles::hms2time( $5, $6, $7, $8 * 10); 
	    $state = 1;
	 } else {
	    s/\[br\]\s*/\n/g;
	    push @$text, $_;
	    $state = 0;
	 }
      }
   }

   $sub->{sub2}->{header} = \@header;
   1;
}

sub write
{
   my ( $self, $sub) = @_;

   my $n = @{$sub->{text}};
   my $i;
   my @ret;
   if ( $sub->{sub2}->{header}) {
      @ret = @{$sub->{sub2}->{header}};
   } else {
     @ret = split "\n", <<HEADER;
[INFORMATION]
[AUTHOR]
[SOURCE]
[PRG]
[FILEPATH]
[DELAY]
[CD TRACK]
[COMMENT]
[END INFORMATION]

[SUBTITLE]
[STYLE]no,[SIZE]18
HEADER
   }
   
   my $from = $sub->{from};
   my $to   = $sub->{to};
   my $text = $sub->{text};
   for ( $i = 0; $i < $n; $i++) {
      my ($fh,$fm,$fs,$fms) = Subtitles::time2hms($from->[$i]);
      my ($th,$tm,$ts,$tms) = Subtitles::time2hms($to->[$i]);
      $fms = int ( $fms / 10 + .5);
      $tms = int ( $tms / 10 + .5);
      my $t = $text->[$i];
      $t =~ s/\n/[br]/g;
      push @ret, 
         sprintf ( "%02d:%02d:%02d.%02d,%02d:%02d:%02d.%02d",
	   $fh,$fm,$fs,$fms,
           $th,$tm,$ts,$tms
	 ),
	 $t,
	 ''
      ;
   }
   \@ret;
}

package Subtitles::Codec::smi;
use vars qw(@ISA);
@ISA=qw(Subtitles::Codec);

sub match
{
   $_[1] =~ m/^<SAMI>/;
}

sub read
{
   my ( $self, $sub, $content) = @_;

   my $line = 0;
# <SAMI>
# <HEAD>
#    <STYLE TYPE="Text/css">
#    <!--
#       P {margin-left: 29pt; margin-right: 29pt; font-size: 24pt; text-align: center; font-family: Tahoma; font-weight: bold; color: #FFFFFF; background-color: #FFFFFF;}
#       .SUBTTL {Name: 'Subtitles'; Lang: en-US; SAMIType: CC;}
#    -->
#    </STYLE>
# </HEAD>
# <BODY>
#    <SYNC START=2002>
#       <P CLASS=SUBTTL>Juon - A curse born of a strong grudge held by someone<br>who died.
#   <SYNC START=7707>
#      <P CLASS=SUBTTL>&nbsp;
#   <SYNC START=7741>
# </BODY>
# </SAMI>

   my $from = $sub->{from};
   my $to   = $sub->{to};
   my $text = $sub->{text};
   my (@header,@footer);

   my $read_header = 1;
   my $read_footer = 0;
   my $state = 0;
   my $fps = $sub->{rate} ? $sub->{rate} : 25;

   for ( @$content) {
      $line++;
      if ( $read_header) {
         if ( m/<BODY>/i) {
	    $read_header = 0;
	 }
         push @header, $_;
      } elsif ( $read_footer) {
         push @footer, $_;
      } else {
         if ( $state == 0 || $state == 2) {
	    if ( m/<\/BODY>/) {
               push @footer, $_;
	       $read_footer = 1; 
	       next;
	    }
	    die "Invalid timestamp at line $line: $_\n" unless m/^(\s*)<\s*SYNC\s*START=(\d+)/i;
	    $state ?
	      push (@$to,   $2/$fps) :
	      push (@$from, $2/$fps);
	    $state++;
	    $sub->{smi}->{s1indent} = length($1) 
	       unless exists $sub->{smi}->{s1indent};
	 } elsif ( $state == 1 || $state == 3) {
	    die "Invalid text at line $line: $_\n" unless m/^(\s*)<\s*P\s*CLASS=(\S+)>(.*)$/i;
	    my ( $s1, $s2, $txt) = ( $1, $2, $3);
	    $txt =~ s/<\s*br\s*>\s*/\n/gi;
	    if ( $txt =~ /^\&nbsp;/) {
               pop @$from if $state == 1; # extra &nbsp;
	       $state = 0;
	    } else {
	       $sub->{smi}->{s2indent} = length($s1) 
		  unless exists $sub->{smi}->{s2indent};
	       $sub->{smi}->{class} = $s2 
		  unless exists $sub->{smi}->{class};
	       push @$from, $$to[-1] + 1/$fps if $state == 3;
	       $state = 2;
	       push @$text, $txt;
	    }
	 }
      }
   }

   $sub->{smi}->{header} = \@header;
   $sub->{smi}->{footer} = \@footer;
   1;
}

sub write
{
   my ( $self, $sub) = @_;

   my $n = @{$sub->{text}};
   my $i;
   my @ret;
   my $from = $sub->{from};
   my $to   = $sub->{to};
   my $text = $sub->{text};
   my $fps = $sub->{rate} ? $sub->{rate} : 25;

   my $smi_class = defined ($sub->{smi}->{class}) ? $sub->{smi}->{class} : 'SUBTTL';
   if ( $sub->{smi}->{header}) {
      @ret = @{$sub->{smi}->{header}};
   } else {
     @ret = split "\n", <<HEADER;
<SAMI>
<HEAD>
   <STYLE TYPE="Text/css">
   <!--
      P {
       margin-left: 29pt; 
       margin-right: 29pt; 
       font-size: 24pt; 
       text-align: center; 
       font-family: Tahoma; 
       font-weight: bold; 
       color: #FFFFFF; 
       background-color: #FFFFFF;
     }
     .SUBTTL {Name: 'Subtitles'; Lang: en-US; SAMIType: CC;}
   -->
   </STYLE>
</HEAD>
<BODY>
HEADER
   }

   my $s1 = ' ' x ( $sub->{smi}->{s1indent} || 0);
   my $s2 = ' ' x ( $sub->{smi}->{s2indent} || 0);
   for ( $i = 0; $i < $n; $i++) {
      my $f = int($$from[$i] * $fps + .5);
      my $t = int($$to[$i] * $fps + .5);
      my $x = $$text[$i];
      $x =~ s/\n/<br>/g;
      push @ret, 
         "$s1<SYNC START=$f>",
	 "$s2<P CLASS=$smi_class>$x",
         "$s1<SYNC START=$t>",
	 "$s2<P CLASS=$smi_class>&nbsp;"
      ;
   }
   if ( $sub->{smi}->{footer}) {
      push @ret, @{$sub->{smi}->{footer}};
   } else {
      push @ret, split "\n", <<FOOTER;
</BODY>
</SAMI>
FOOTER
   }
   \@ret;
}

sub downgrade
{
   for ( @{$_[1]->{text}}) {
      s/<[^\>]*>//g;
      s/{[^\}]*}//g;
   }
}

1;

=pod

=head1 NAME

Subtitles - fix timing for subtitles in various text formats

=head1 DESCRIPTION

Movie files can be viewed with subtitles, which are currently
very popular as text files. C<Subtitles> provides means for
simple loading, re-timing, and storing these subtitle files.
A command-line tool F<subs> for the same purpose and using
C<Subtitles> interface is included in the distribution.

The module supports C<srt>, C<sub>, C<smi> subtitle formats.

Time values are floats, in seconds with millisecond precision.

=head1 SYNOPSIS

   use Subtitles;

   open F, 'Ichi The Killer.sub' or die "Cannot read:$!";
   
   my $sub = load(\*F);
   close F;

   die "error:$@\n" unless $sub;

   # back two minutes
   $sub-> shift( $sub-> parse_time('-02:00')); 

   # re-frame from 25 fps
   $sub-> scale( 23.976 / 25 );

   # or both
   $sub-> transform( -120, 0.96);

   # split for 2 parts
   my ( $part1, $part2) = $sub-> split( $self-> length / 2);

   # join back with 5-second gap 
   $sub = $part1-> join( $part2, 5);

   # save
   open F, "> out.sub" or die "Cannot write:$!\n";
   $sub-> save( \*F);
   close F;

   # report
   print "sub is ", time2str( $sub-> length);

=head1 API

=head2 Package methods

=over

=item codecs

Returns array of installed codecs.

=item hms2time HOURS, MINUTES, SECONDS, MILLISECONDS

Combines four parameters into float time in seconds.

=item time2hms TIME

Splits time into four integers, - hours, minutes, seconds, and milliseconds.
If time is less than zero, zero times are returned.

=item time2shms

Splits time into five integers, - time sign, hours, minutes, seconds, and milliseconds.

=item time2str TIME

Converts time to a human-readable string.

=back

=head2 Object methods

=over

=item clear

Removes all content

=item codec [ STRING ]

If STRING is not defined, returns currently associated codec.
Otherwise, sets the new codec in association. The STRING is
the codec's package name, such as C<Subtitles::Codec::srt>.

=item dup [ CLEAR ]

Duplicates object instance in deep-copy fashion. If CLEAR
flag is set, timeframes are not copied.

=item join GUEST, GAP

Adds content of object GUEST at the end of the list of subtitles with GAP in seconds.

=item length

Returns length of subtitle span.

=item load FH [ CODEC ]

Reads subtitle content into object. If successful, returns 1;
otherwise undef is returned and C<$@> contains the error.

By default, tries to deduce which codec to use; to point the
selection explicitly CODEC string is to be used.

=item lines

Returns number of subtitle cues.

=item new

Creates a new instance. To force a particular
codec, supply C<codec> string here.

=item parse_time STRING

Parses STRING which is either a C<[[HH:]MM:]SS[,MSEC]> string
or string in a format specific to a codec, for example, number
of a frame. 

=item rate FPS

Forces a particluar frame-per-second rate, if a codec
can make use of it.

=item save FH

Writes content of instance into FH file handle,
using the associated codec.

=item scale A

Changes time-scale. If A is 2, the subtitles 
go off 2 times slower, if 0.5 - two times faster, etc.

=item shift B

Shifts timings by B seconds. B can be negative.

=item split TIME

Splits the content of the instance between
two newly created instances of the same class,
by TIME, and returns these. The both resulting 
subtitles begin at time 0.

=item transform A, B

Applies linear transformation to the time-scale,
such as C<u = At + B> where C<t> is the original 
time and C<u> is the result.

=back

=head1 BUGS

This is alpha code, more a proof-of-concept rather
that anything else, so most surely bugs are lurking.

Anyway: not all subtitle types are recognized.
The modules doesn't handle multi-language subtitles.

=head1 SEE ALSO

L<subs> - command-line wrapper for this module

=head1 THANKS

L<http://dvd.box.sk/>, L<http://subs.2ya.com>.

=head1 AUTHOR

Dmitry Karasik, E<lt>dmitry@karasik.eu.orgE<gt>.

=cut
