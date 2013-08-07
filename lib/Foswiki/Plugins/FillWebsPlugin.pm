# See bottom of file for default license and copyright information

=begin TML

---+ package Foswiki::Plugins::FillWebsPlugin


=cut

# change the package name!!!
package Foswiki::Plugins::FillWebsPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version

our $VERSION          = '0.1';
our $RELEASE          = '0.1';

# One line description of the module
our $SHORTDESCRIPTION = 'Makes sure every web has a certain set of topics.';
our $NO_PREFS_IN_TOPIC = 1;

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerRESTHandler( 'fill', \&restFill );

    # Plugin correctly initialized
    return 1;
}

sub restFill {
    my ( $session, $subject, $verb, $response ) = @_;

    my $allowed = $Foswiki::cfg{Plugins}{FillWebsPlugin}{Allowed} || $Foswiki::cfg{SuperAdminGroup} || 'admin';
    unless ( _isAllowed($allowed)  ) {
        return 'You are not allowed to do this!';
    }

    my $query = $session->{request};

    my $srcWeb = $query->{param}->{srcweb} || [ '_default' ];
    my $target = $query->{param}->{target};
    my $recurseSrc = $query->{param}->{recursesrc};
    $recurseSrc = $recurseSrc->[0] if $recurseSrc;
    my $recursive = $query->{param}->{recursive};
    $recursive = $recursive->[0] if $recursive;
    my $skipWebs = $query->{param}->{skipwebs};
    if ( $skipWebs && $skipWebs->[0] ) {
        $skipWebs = $skipWebs->[0];
    } else {
        $skipWebs = '.*'; # do nothing if parameter is not provided
    }
    my $createWeb = $query->{param}->{createweb};
    $createWeb = $createWeb->[0] if $createWeb;
    my $maxdepth = $query->{param}->{maxdepth};
    if( $maxdepth ) {
        $maxdepth = $maxdepth->[0];
    } else {
        $maxdepth = 10;
    }
    my $redirect = $query->{param}->{redirect};
    my ( $web, $topic );
    if( $redirect ) {
        ( $web, $topic ) = Foswiki::Func::normalizeWebTopicName( '', $redirect->[0] );
    } else {
        ( $web, $topic ) = qw( %SYSTEM% FillWebsPlugin );
    }

    $srcWeb = (Foswiki::Func::normalizeWebTopicName( $srcWeb->[0], 'WebHome' ))[0];
    unless( Foswiki::Func::webExists( $srcWeb ) ) {
        return "Source web '$srcWeb' does not exist!";
    }

    my ( $actions, $errors ) = ('', '');

    if($target && $target->[0]) {
        $target = (Foswiki::Func::normalizeWebTopicName( $target->[0], 'WebHome' ))[0];
        unless( Foswiki::Func::webExists( $target ) ) {
            if ( $createWeb ) {
                unless ( Foswiki::Func::isValidWebName( $target ) ) {
                    my $url = Foswiki::Func::getScriptUrl(
                        $web, $topic, 'oops',
                        template => "oopsgeneric",
                        param1   => "Invalid web name '$target'!",
                        param2   => "The name of the web you specified ($target) is invalid."
                    );
                    Foswiki::Func::redirectCgiQuery( undef, $url );
                }

                Foswiki::Func::createWeb( $target, $srcWeb );
                $actions .= "\n\nCreated web '$target'";
            } else {
                my $url = Foswiki::Func::getScriptUrl(
                    $web, $topic, 'oops',
                    template => "oopsgeneric",
                    param1   => "Target web '$target' does not exist!",
                    param2   => "The web you specified ($target) does not exist and you are not creating a new web."
                );
                Foswiki::Func::redirectCgiQuery( undef, $url );
            }
        }

        my ( $subActions, $subErrors ) = _fill($srcWeb, $recurseSrc, $target, $recursive, $skipWebs, 1, $maxdepth);
        $actions .= $subActions;
        $errors .= $subErrors;
    } else {
        foreach my $eachWeb (Foswiki::Func::getListOfWebs('user')) {
            next if ( $eachWeb =~ m#/# );
            my ( $subActions, $subErrors ) = _fill($srcWeb, $recurseSrc, $eachWeb, $recursive, $skipWebs, 1, $maxdepth );
            $actions .= $subActions;
            $errors .= $subErrors;
        }
    }

    $actions = "none" unless $actions;
    $actions = "Actions performed: $actions";

    $errors = "HOWEVER there were ERRORS: $errors" if $errors;

    throw Foswiki::OopsException(
        'oopsgeneric',
        web    => $web,
        topic  => $topic,
        params => ['Operation finished!', $actions, $errors ]
    );
}

sub _fill {
    my ( $srcWeb, $recurseSrc, $target, $recurseTarget, $skipWebs, $depth,  $maxdepth ) = @_;

    my $levelstring = ' * ' x $depth;

    return ('', "\n\n${levelstring}maxdepth ($maxdepth) has been reached!") if ( $maxdepth <= $depth );

    return ('', '') if ( $target =~ m#$skipWebs# ); # I trust that authorized users provide valid regexes

    # I suppose efficiancy is not so much of an issue, so I re-read the
    # webs/topics for every web I process...
    my @topics = Foswiki::Func::getTopicList( $srcWeb );

    # list of direct subwebs in source.
    my @srcSubwebs = ( ( $recurseSrc ) ? _getDirectSubwebs($srcWeb) : () );

    my $actionString = '';
    my $errorString = '';

    foreach my $topic ( @topics ) {
        my ( $meta, $text ) = Foswiki::Func::readTopic( $srcWeb, $topic );

        # copy topic (text)
        unless ( Foswiki::Func::topicExists( $target, $topic ) ) {
            Foswiki::Func::saveTopic( $target, $topic, $meta, $text );
            $actionString .= "\n\n${levelstring}copied '$topic'";
        }

        # copy attachments
        foreach my $attachment ( $meta->find( 'FILEATTACHMENT' ) ) {
            my $filename = $attachment->{attachment};
            unless ( -e "$Foswiki::cfg{PubDir}/$srcWeb/$topic/$filename" ) {
                my $message = "Source attachment '$srcWeb/$topic/$filename' does not exist!";
                Foswiki::Func::writeWarning($message);
                $errorString .= "\n\n${levelstring}$message";
                next;
            }
            next if -e "$Foswiki::cfg{PubDir}/$target/$topic/$filename";
            Foswiki::Func::copyAttachment( $srcWeb, $topic, $filename, $target, $topic, $filename );
            $actionString .= "\n\n${levelstring}copied attachment '$target/$topic/$filename'";
        }
    }

    if ( $recurseSrc ) {
        foreach my $eachWeb ( @srcSubwebs ) {
            my $subTarget = "$target/$eachWeb";
            my $subSrc = "$srcWeb/$eachWeb";
            Foswiki::Func::writeWarning("handling $eachWeb for $subTarget");
            unless ( Foswiki::Func::webExists( $subTarget ) ) {
                Foswiki::Func::createWeb( $subTarget, $subSrc );
                my $message .= "Created web $subTarget";
                Foswiki::Func::writeWarning( $message );
                $actionString .= "\n\n${levelstring}$message";
            }

            my ( $subActions, $subErrors ) = _fill($subSrc, $recurseSrc, $subTarget, $recurseTarget, $skipWebs, $depth + 1, $maxdepth);
            $actionString .= $subActions;
            $errorString .= $subErrors;
        }
    }

    if ( $recurseTarget ) {
        foreach my $targetSub ( _getDirectSubwebs( $target ) ) {
            my $skip;
            foreach my $srcsub ( @srcSubwebs ) {
                if ( $targetSub eq $srcsub ) {
                    $skip = 1;
                }
            }
            next if $skip;

            my ( $subActions, $subErrors ) = _fill($srcWeb, $recurseSrc, "$target/$targetSub", $recurseTarget, $skipWebs, $depth + 1, $maxdepth);
            $actionString .= $subActions;
            $errorString .= $subErrors;
        }
    }

    $actionString = "\n\n${levelstring}web: ${target}$actionString" if $actionString;
    $errorString = "\n\n${levelstring}web: ${target}$errorString" if $errorString;

    return ( $actionString, $errorString );
}

sub _getDirectSubwebs {
    my ( $srcWeb ) = @_;

    my @srcSubwebs = ();

    foreach my $sub ( Foswiki::Func::getListOfWebs('user', $srcWeb) ) {
        if ( $sub =~ m#^$srcWeb/([^/]+)$# ) {
            push( @srcSubwebs, $1 );
        }
    }

    return @srcSubwebs;
}

# XXX Copy/Paste/Modify KVPPlugin
sub _isAllowed {
    my ($allow) = @_;

    # Always allow members of the admin group to edit
    return 1 if ( Foswiki::Func::isAnAdmin() );

    if (
            ref( $Foswiki::Plugins::SESSION->{user} )
            && $Foswiki::Plugins::SESSION->{user}->can("isInList")
        )
    {
        return $Foswiki::Plugins::SESSION->{user}->isInList($allow);
    }
    elsif ( defined &Foswiki::Func::isGroup ) {
        my $thisUser = Foswiki::Func::getWikiName();
        foreach my $allowed ( split( /\s*,\s*/, $allow ) ) {
            ( my $waste, $allowed ) =
              Foswiki::Func::normalizeWebTopicName( undef, $allowed );
            if ( Foswiki::Func::isGroup($allowed) ) {
                return 1 if Foswiki::Func::isGroupMember( $allowed, $thisUser );
            }
            else {
                $allowed = Foswiki::Func::getWikiUserName($allowed);
                $allowed =~ s/^.*\.//;    # strip web
                return 1 if $thisUser eq $allowed;
            }
        }
    }

    return 0;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2013 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.