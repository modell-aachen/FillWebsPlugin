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

    Foswiki::Func::registerRESTHandler( 'fill', \&restFill,
        authenticate => 1, http_allow => 'POST,GET', validate => 1
    );
    Foswiki::Func::registerRESTHandler( 'reset', \&restReset,
        authenticate => 1, http_allow => 'POST,GET', validate => 1
    );

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
    my $skipTopics = $query->param( 'skiptopics' );
    if($skipTopics) {
        $skipTopics = qr#$skipTopics#;
    }
    my $keepSymlinks = $query->param( 'keepsymlinks' );
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

                my ($createAction, $createErrors) = _createOrLinkWeb($target, $srcWeb, '', $keepSymlinks);
                $actions .= $createAction;
                $errors .= $createErrors;
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

        my ( $subActions, $subErrors ) = _fill($srcWeb, $recurseSrc, $target, $recursive, $skipWebs, $skipTopics, 1, $maxdepth, $keepSymlinks);
        $actions .= $subActions;
        $errors .= $subErrors;
    } else {
        foreach my $eachWeb (Foswiki::Func::getListOfWebs('user')) {
            next if ( $eachWeb =~ m#/# );
            my ( $subActions, $subErrors ) = _fill($srcWeb, $recurseSrc, $eachWeb, $recursive, $skipWebs, $skipTopics, 1, $maxdepth, $keepSymlinks );
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

sub _createOrLinkWeb {
    my ( $target, $srcWeb, $levelstring, $keepSymlinks ) = @_;

    if ( $keepSymlinks ) {
        my $dir = "$Foswiki::cfg{DataDir}/$srcWeb";
        if ( -l $dir ) {
            my $actionString = "\n\n${levelstring}web: ${target}";
            $levelstring .= ' * ';

            my $newDir = "$Foswiki::cfg{DataDir}/$target";
            my $dst = readlink($dir);
            unless ( -e $newDir ) {
                $actionString .= "\n\n${levelstring}data-dir symlinked";
                symlink $dst, $newDir;
            } else {
                unless ( -l $newDir ) {
                    return ( $actionString, "\n\nCould not link '$newDir' to '$dst' because it already exists and is no symbolic link" );
                }
                unless ( readlink($newDir) eq $dst ) {
                    return ( $actionString, "\n\nCould not link '$newDir' to '$dst' because it already exists and points to " . readlink($newDir) );
                }
                $actionString .= "\n\n${levelstring}data-dir already symlinked";
            }

            my $pubDir = "$Foswiki::cfg{PubDir}/$srcWeb";
            if ( -e $pubDir ) {
                my $newPubDir = "$Foswiki::cfg{PubDir}/$target";
                unless ( -l $pubDir ) {
                        return ( $actionString, "\n\nCould not link '$newPubDir' because '$pubDir' is not a symbolic link" );
                }
                my $pubDst = readlink($pubDir);
                unless ( -e $newPubDir ) {
                    $actionString .= "\n\n${levelstring}pub-dir symlinked";
                    symlink $pubDst, $newPubDir;
                } else {
                    if ( -l $newPubDir && readlink($newPubDir) eq $dst ) {
                        $actionString .= "\n\n${levelstring}pub-dir already symlinked";
                    } else {
                        return ( $actionString, "\n\nCould not link '$newPubDir' to '$pubDst'" );
                    }
                }
            }

            return ( $actionString, '' );
        }
    }

    Foswiki::Func::createWeb( $target, $srcWeb );
    return ("\n\n${levelstring}Created web '$target'", '');
}

sub restReset {
    my ( $session, $subject, $verb, $response ) = @_;

    my $allowed = $Foswiki::cfg{Plugins}{FillWebsPlugin}{Allowed} || $Foswiki::cfg{SuperAdminGroup} || 'admin';
    unless ( _isAllowed($allowed)  ) {
        return 'You are not allowed to do this!';
    }

    my $query = Foswiki::Func::getCgiQuery();
    my $resetweb = $query->param( 'resetweb' );
    my $srcweb = $query->param( 'srcweb' );
    my $skiptopics = $query->param( 'skiptopics' );
    if($skiptopics) {
        $skiptopics = qr#$skiptopics#;
    }
    my $keepSymlinks = $query->param( 'keepsymlinks' );

    my $actions = '';
    my $errors = '';

    unless ( Foswiki::Func::webExists( $srcweb ) ) {
        return "Template '$srcweb' does not exist.";
    }

    unless ( Foswiki::Func::isValidWebName( $resetweb ) ) {
        my $url = Foswiki::Func::getScriptUrl(
            $Foswiki::cfg{UsersWebName}, $Foswiki::cfg{HomeTopicName}, 'oops',
            template => "oopsgeneric",
            param1   => "Invalid web name '$resetweb'!",
            param2   => "The name of the web you specified ($resetweb) is invalid."
        );
        Foswiki::Func::redirectCgiQuery( undef, $url );
    }

    if( Foswiki::Func::webExists($resetweb) ) {
        # find free web in trash
        my $trash = $Foswiki::cfg{TrashWebName};
        my $count = 0;
        my $trashname;
        my $reset_esc = $resetweb;
        $reset_esc =~ s#[/.]#_#g;
        do {
            $trashname = "$trash/${reset_esc}_$count";
            $count++;
        } while ( Foswiki::Func::webExists( $trashname ) );

        Foswiki::Func::moveWeb( $resetweb, $trashname );
        $actions .= "\n\nMoved web to trash: '$resetweb'";
    }

    my ($createAction, $createErrors) = _createOrLinkWeb($resetweb, $srcweb, '', $keepSymlinks);
    $actions .= $createAction;
    $errors .= $createErrors;

    my( $subActions, $subErrors ) = _fill( $srcweb, 1, $resetweb, 1, undef, $skiptopics, 0, 5, $keepSymlinks );
    $actions .= $subActions;
    $errors .= $subErrors;

    $actions = "none" unless $actions;
    $actions = "Actions performed: $actions";

    $errors = "HOWEVER there were ERRORS: $errors" if $errors;

    throw Foswiki::OopsException(
        'oopsgeneric',
        web    => $resetweb,
        topic  => $Foswiki::cfg{HomeTopicName},
        params => ["Web '$resetweb' was reset!", $actions, $errors ]
    );
}

sub _fill {
    my ( $srcWeb, $recurseSrc, $target, $recurseTarget, $skipWebs, $skipTopics, $depth,  $maxdepth, $keepSymlinks ) = @_;

    my $levelstring = ' * ' x $depth;

    return ('', "\n\n${levelstring}maxdepth ($maxdepth) has been reached!") if ( $maxdepth <= $depth );

    return ('', '') if ( $target =~ m#$skipWebs# ); # I trust that authorized users provide valid regexes

    my $actionString = '';
    my $errorString = '';

    my $dir = "$Foswiki::cfg{DataDir}/$target";
    if ( -l $dir ) {
        if ( $keepSymlinks ) {
            my $target = readlink($dir);
            my $srcDir = "$Foswiki::cfg{DataDir}/$srcWeb";
            $srcDir = readlink($srcDir) if -l $srcDir;
            unless ( $srcDir eq $target ) {
                return ('', "Symbolic link '$dir' is not pointing to $target");
            }
            return ('', '');
        } else {
            return ('', "Found symbolic link '$dir', but not keeping symlinks.");
        }
    }

    # I suppose efficiancy is not so much of an issue, so I re-read the
    # webs/topics for every web I process...
    my @topics = Foswiki::Func::getTopicList( $srcWeb );

    # Sort topics to copy forms first
    my @formTopics = grep { $_ =~ /.*Form$/ } @topics;
    my @nonFormTopics = grep { $_ !~ /.*Form$/ } @topics;
    @topics = @formTopics;
    push(@topics, @nonFormTopics);

    # list of direct subwebs in source.
    my @srcSubwebs = ( ( $recurseSrc ) ? _getDirectSubwebs($srcWeb) : () );

    foreach my $topic ( @topics ) {
        next if $skipTopics && $topic =~ m#$skipTopics#;

        if ( $keepSymlinks ) {
            my $txtFile = "$Foswiki::cfg{DataDir}/$srcWeb/$topic.txt";
            if ( -l $txtFile ) {
                my $links = {
                    $txtFile => "$Foswiki::cfg{DataDir}/$target/$topic.txt",
                    "$txtFile,v" => "$Foswiki::cfg{DataDir}/$target/$topic.txt,v",
                    "$Foswiki::cfg{DataDir}/$srcWeb/$topic,pfv" => "$Foswiki::cfg{DataDir}/$target/$topic,pfv",
                    "$Foswiki::cfg{PubDir}/$srcWeb/$topic" => "$Foswiki::cfg{PubDir}/$target/$topic",
                };
                my $gotProblems;
                foreach my $src ( keys %$links ) {
                    next unless -e $src;
                    my $dst = $links->{$src};
                    $src = readlink($src) if -l $src;
                    if ( -e $dst ) {
                        next if -l $dst && readlink($dst) eq $src;
                        $errorString .= "\n\n${levelstring}Could not symlink $srcWeb.$topic, because $dst already exists but points to ".readlink($dst)."!";
                        $gotProblems = 1;
                    }
                }
                unless ( $gotProblems ) {
                    foreach my $src ( keys %$links ) {
                        next unless -e $src;
                        my $dst = $links->{$src};
                        $src = readlink($src) if -l $src;
                        next if -e $dst;

                        $src = Foswiki::Sandbox::untaintUnchecked($src);
                        $dst = Foswiki::Sandbox::untaintUnchecked($dst);
                        symlink $src, $dst;
                        $actionString .= "\n\n${levelstring}symlinked '$src' to '$dst'";
                    }
                }

                next;
            }
        }

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
                my ($createAction, $createErrors) = _createOrLinkWeb($subTarget, $subSrc, $levelstring, $keepSymlinks);
                $actionString .= $createAction;
                $errorString .= $createErrors;
            }

            my ( $subActions, $subErrors ) = _fill($subSrc, $recurseSrc, $subTarget, $recurseTarget, $skipWebs, $skipTopics, $depth + 1, $maxdepth, $keepSymlinks);
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

            my ( $subActions, $subErrors ) = _fill($srcWeb, $recurseSrc, "$target/$targetSub", $recurseTarget, $skipWebs, $skipTopics, $depth + 1, $maxdepth, $keepSymlinks);
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
