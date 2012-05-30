package AnyEvent::Gearman::Worker::RetryConnection;

# ABSTRACT: patching AnyEvent::Gearman::Worker:Connection

our $VERSION = '0.4'; # VERSION 

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($ERROR);

use namespace::autoclean;
use Scalar::Util 'weaken';
 
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Any::Moose;

use Data::Dumper;

has retry_count=>(is=>'rw',isa=>'Int',clearer=>'reset_retry',default=>sub{0});
has retry_timer=>(is=>'rw',isa=>'Object',clearer=>'reset_timer');
has registered=>(is=>'ro',isa=>'HashRef',default=>sub{return {};});
extends 'AnyEvent::Gearman::Worker::Connection';
override connect=>sub{
    my ($self) = @_;
 
    # already connected
    return if $self->handler;
 
    my $g = tcp_connect $self->_host, $self->_port, sub {
        my ($fh) = @_;
 
        if ($fh) {
            my $handle = AnyEvent::Handle->new(
                fh       => $fh,
                on_read  => sub { $self->process_packet },
                on_error => sub {
                    my ($hdl, $fatal, $msg) = @_;

                    DEBUG $fatal;
                    DEBUG $msg;

                    my @undone = @{ $self->_need_handle },
                                 values %{ $self->_job_handles };
                    $_->event('on_fail') for @undone;
 
                    $self->_need_handle([]);
                    $self->_job_handles({});
                    $self->mark_dead;
                    
                    $self->retry_connect();
                },
            );
 
            $self->handler( $handle );
            $_->() for map { $_->[0] } @{ $self->on_connect_callbacks };
            
            DEBUG "connected"; 
            if( $self->retry_count > 0 )
            {
                foreach my $key (keys %{$self->registered})
                {
                    DEBUG "re-register '".$key."'";
                    $self->register_function($key,$self->registered->{$key});
                }
            }
            $self->reset_retry;
            $self->reset_timer;

        }
        else {
            $self->retry_connect;
            return;
        }
 
        $self->on_connect_callbacks( [] );
    };
 
    weaken $self;
    $self->_con_guard($g);
 
    $self;
};

after 'register_function'=>sub{
    my $self = shift;
    $self->registered->{$_[0]} = $_[1];
};

sub retry_connect{
    my $self = shift;
    if( !$self->retry_timer ){
        my $timer = AE::timer 0.1,0,sub{
            DEBUG "retry connect";
            $self->retry_count((!!$self->retry_count)+1);
            $self->connect();
            $self->reset_timer;
        };
        $self->retry_timer($timer);
    }
}

sub patch_worker{
    my $worker = shift;
    my $js = $worker->job_servers();
    for(my $i=0; $i<@{$js}; $i++)
    {
        $js->[$i] = __PACKAGE__->new(hostspec=>$js->[$i]->hostspec);
    }
    return $worker;
}
1;

__END__
=pod

=head1 NAME

AnyEvent::Gearman::Worker::RetryConnection - patching AnyEvent::Gearman::Worker:Connection

=head1 VERSION

version 0.4

=head1 AUTHOR

KHS, HyeonSeung Kim <sng2nara@hanmail.net>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by HyeonSeung Kim.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

