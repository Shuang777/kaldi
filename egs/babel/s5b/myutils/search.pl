#!/usr/bin/perl -w
use threads;
use threads::shared;
use strict;
use warnings;
use Storable qw(dclone);

my $start_key1 = 0.1;
my $start_key2 = 1;
my $max_iter = 6;

sub get_new_keys {
  my @values = @{$_[0]};
  my @new_keys = ();
  if (@values == 0) {
    push @new_keys, $start_key1;
    push @new_keys, $start_key2;
  } else {
    my @list_values = @{dclone(\@values)};
    @list_values = sort {$a->[0] <=> $b->[0]} @list_values;
    my $count = 0;
    for my $i (0..$#list_values) {
      unshift @{$list_values[$i]}, $count;
      $count++;
    }
    my @sort_values = sort {$a->[2] <=> $b->[2]} @list_values;
    my $first_index = $sort_values[0][0];
    my $second_index = $sort_values[1][0];
    abs($first_index - $second_index) == 1 || die "smallest term $sort_values[0][1] (rank $first_index) and second smallest term $sort_values[1][1] (rank $second_index) are not next to each other.\n";
    if ($first_index == 0) {
      push @new_keys, $sort_values[0][1]/10;
    } elsif ($first_index == $#sort_values) {
      push @new_keys, $sort_values[0][1]*10;
    } else {
      my $third_index = 2 * $first_index - $second_index;
      push @new_keys, ($list_values[$third_index][1] + $sort_values[0][1]) / 2;
    }
    push @new_keys, ($sort_values[0][1] + $sort_values[1][1]) / 2;
  }
  return @new_keys;
}

sub runfunc {
  my $value = $_[0];
  my $cmd = $_[1];
  $$value = `$cmd`;
}

print $0 . " ". (join " ", @ARGV) . "\n";

my $cmd = $ARGV[0];

my @values = ();

my $iter = 0;
while ($iter < $max_iter) {
  my @new_keys = &get_new_keys(\@values);
  print "new keys to try @new_keys\n";
  my @new_values = ();
  share(@new_values);
  my @t;
  for my $i (0..$#new_keys) {
    my $key = $new_keys[$i];
    my $cmdt = $cmd;
    $cmdt =~ s/\#0/$key/g;
    $t[$i] = threads->create( \&runfunc, \$new_values[$i], $cmdt);
  }
  for my $i (0..$#new_keys) {
    $t[$i]->join();
    push @values, [ ($new_keys[$i], $new_values[$i]) ];
    print "key $new_keys[$i]\t value $new_values[$i]\n";
  }
  @values = sort {$a->[1] <=> $b->[1]} @values;
  print "best key $values[0][0] value $values[0][1]\n";
  $iter++;
}

