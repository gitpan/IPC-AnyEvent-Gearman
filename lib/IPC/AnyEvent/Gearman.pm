package IPC::AnyEvent::Gearman;
# ABSTRACT: IPC through gearmand.
use namespace::autoclean;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);
use Any::Moose;
use Data::Dumper;
use AnyEvent::Gearman;
use AnyEvent::Gearman::Worker::RetryConnection;


our $VERSION = '0.6'; # VERSION


has 'pid' => (is => 'rw', isa => 'Str', default=>sub{return $$;});

has 'job_servers' => (is => 'rw', isa => 'ArrayRef',required => 1);

has 'prefix' => (is => 'rw', isa => 'Str', default=>'IPC::AnyEvent::Gearman#');

has 'on_recv' => (is => 'rw', isa=>'CodeRef', 
    default=>sub{return sub{WARN 'You need to set on_recv function'};}
);
has 'on_sent' => (is => 'rw', isa=>'CodeRef', 
    default=>sub{return sub{INFO 'Send OK '.$_[0]};}
);
has 'on_fail' => (is => 'rw', isa=>'CodeRef', 
    default=>sub{return sub{WARN 'Send FAIL '.$_[0]};}
);

has 'client' => (is=>'rw', lazy=>1, isa=>'Object',
default=>sub{
    DEBUG 'lazy client';
    my $self = shift;
    return gearman_client @{$self->job_servers()};
},
);

has 'worker' => (is=>'rw', isa=>'Object',
                    );

after 'pid' => sub{
    my $self = shift;
    if( @_ && $self->{listening}){
        $self->_renew_connection();    
    }
};

after 'prefix' => sub{
    my $self = shift;
    if( @_ && $self->{listening}){
        $self->_renew_connection();    
    }
};

after 'job_servers' => sub{
    my $self = shift;
    if( @_ && $self->{listening}){
        $self->_renew_connection();    
    }
    if( @_ ){
        $self->client( gearman_client @{$self->job_servers()} );
    }
};

sub listen{
    my $self = shift;
    $self->{listening} = 1;
    $self->_renew_connection();
}

sub channel{
    my $self = shift;
    my $pid = shift;
    $pid = $self->pid() unless( $pid );
    return $self->prefix().$pid;
}

sub send{
    my $self = shift;
    my $target_pid = shift;
    my $data = shift;
    $self->client->add_task(
        $self->channel($target_pid) => $data,
        on_complete => sub{
            my $result = $_[1];
            $self->on_sent()->($self->channel($target_pid),$_[1]);
        },
        on_fail => sub{
            $self->on_fail()->($self->channel($target_pid));
        }
    );
}

sub _renew_connection{
    my $self = shift;
    DEBUG "new Connection";
    my $worker = gearman_worker @{$self->job_servers()};
    $worker = AnyEvent::Gearman::Worker::RetryConnection::patch_worker($worker);
    $self->worker( $worker );
    $self->worker->register_function(
        $self->prefix().$self->pid() => sub{
            my $job = shift;
            my $res = $self->on_recv()->($job->workload);
            $res = '' unless defined($res);
            $job->complete($res);
        }
    );
}

__PACKAGE__->meta->make_immutable;

1;

__END__
=pod

=head1 NAME

IPC::AnyEvent::Gearman - IPC through gearmand.

=head1 VERSION

version 0.6

=head1 SYNOPSIS

    use AnyEvent;
    use IPC::AnyEvent::Gearman;
    
    #receive    
    my $recv = IPC::AnyEvent::Gearman->new(job_servers=>['localhost:9999']);
    $recv->on_recv(sub{
        my $msg = shift;
        print "received msg : $data\n";
        return "OK";#result
    });
    $recv->listen();

    my $cv = AE::cv;
    $cv->recv;

    #send
    my $send = IPC::AnyEvent::Gearman->new(server=>['localhost:9999']);
    $send->pid(1102);
    my $result = $send->send("TEST DATA");

=head1 ATTRIBUTES

=head2 pid

'pid' is unique id for identifying each process.
This can be any value not just PID.
It is filled own PID by default.

=head2 job_servers

ArrayRef of hosts.

=head2 prefix

When register function, it uses prefix+pid as function name.
It is filled 'IPC::AnyEvent::Gearman#' by default. 

=head2 on_recv

on_recv Hander.
First argument is DATA which is sent.
This can be invoked after listen().

=head2 on_sent

on_sent handler.
First argument is a channel string.

=head2 on_fail

on_fail handler.
First argument is a channel string.

=head1 METHODS

=head2 listen

To receive message, you MUST call listen().

=head2 channel

get prefix+pid

=head2 send

To send data to process listening prefix+pid, use this.

    my $sender = IPC::AnyEvent::Gearman->new(job_servers=>['localhost:9998']);
    $sender->prefix('MYIPC');
    $sender->send(1201,'DATA');

=head1 AUTHOR

KHS, HyeonSeung Kim <sng2nara@hanmail.net>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by HyeonSeung Kim.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

