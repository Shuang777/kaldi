#!/usr/bin/env perl

# Given the keyword list xml file and single-word-to-surface-forms mapping file, 
# generate a keyword-to-surface-forms mapping file based on the cross product
# of the surface forms from each component word of a keyword.

# For any word in the keyword list xml that cannot find a surface form in the input
# single-word-to-surface-forms mapping file, we would just use the word itself as
# the surface form for that word.

# The word_surface_form_file could be "None". In that case, the output surface forms
# of the keywords would be just the keywords themselves.

use warnings;

@ARGV == 3 || die "$0 <term_list_xml> <word_surface_form_file [None|*]> <output_keywords_surface_form_file>\n";

$termList = shift @ARGV;
$wordSurfaceFormFile = shift @ARGV;
$outKeywordSurfaceFormFile = shift @ARGV;

&loadTerms($termList);

$surfaceFormHashRef = &loadSurfaceForm($wordSurfaceFormFile);

&CreateKwTermSurfaceForm($outKeywordSurfaceFormFile);

exit;

# load keyword terms from the kwlist file
sub loadTerms
{
    my ($file) = @_;

    my($count, $term, $termid, @termids);

    print "Loading terms...\n";
    open(IN, $file) || die "Cannot open $file\n";
    
    @termids = ();
    $count = 0;
    while(<IN>)
    {
	if (/<kw kwid/)
	{
	    ($termid) = /kwid=\"([A-Za-z0-9_\-]+)\">/;
	    defined($termid) || die "Unexpected format\n$_\nstopped";
	    
	    push (@termids, $termid);

	    $_ = <IN>;
	    ($term) = /<kwtext>\s*(.*?)\s*<\/kwtext>/;
	    defined($term) || die "Unexpected format\n$_\nstopped";

	    die "Duplicate terms\n$_\nstopped" if defined($termHash{$term});
	    
	    $termHash{$term} = $termid;

	    $count++;
	}
    }

    close IN;

    print "Loaded $count terms from $file\n";
    return @termids;
}

# load surface form for invidiual words from file
sub loadSurfaceForm
{
    my ($file) = @_;

    my($word_count, $surface_count, $word, $surface, %surfaceFormsHash, %uniqEntries);

    %surfaceFormsHash = ();
    %uniqEntries = ();
    $word_count = 0;
    $surface_count = 0;

    print "Loading single-word surface forms...\n";

    if ($file eq "None")
    {
        print "No word surface form file. Use the words themselves as the surface form.\n";
        return \%surfaceFormsHash;
    }

    open(IN, $file) || die "Cannot open $file\n";

    while(<IN>)
    {
        chomp;

        if (defined $uniqEntries{$_})
        {
            next;
        }
        else
        {
            $uniqEntries{$_} = 1;
        }

        ($word, $surface) = split(/\t/, $_, 2);

        unless (defined $surfaceFormsHash{$word})
        {
            my @surface_array = ();
            $surfaceFormsHash{$word} = \@surface_array;
            $word_count++;
        }
        push(@{$surfaceFormsHash{$word}}, $surface);
        $surface_count++;
    }

    close IN;

    print "Loaded $surface_count surface forms for $word_count words from $file\n";
    return \%surfaceFormsHash;
}

# construct multiple surface forms for each keyword term:
# for single word terms, use all surface forms for the word
# for multiple word terms, use all cross-product surface forms from each individual words
sub CreateKwTermSurfaceForm
{
    my ($outfile) = @_;

    foreach $term (keys %termHash)
    {
	@tokens = split(/ /, $term);

	my $cross_product_surfaces_ref = &getCrossProductSurfaces(\@tokens);

	if (defined $termSurfaceHash{$term}) {
		die "Error: Duplicate term: $term\n";
	} else {
		$termSurfaceHash{$term} = $cross_product_surfaces_ref;
	}

    }

    print "Printing keyword terms surface forms...\n";
    open(OUT, ">$outfile") || die "Cannot open $outfile\n";
    
    my $total_kw_count = 0;
    my $total_surface_count = 0;
    foreach $term (sort(keys %termHash))
    {
        foreach $surface (sort @{ $termSurfaceHash{$term} })
	{
	   print OUT "$term\t$surface\n";
	   $total_surface_count++;
	}
	$total_kw_count++;
    }
    close OUT;

    print "Printed $total_surface_count surface forms for $total_kw_count keywords.\n";
}

# get all cross-product surface forms from a sequence of words
sub getCrossProductSurfaces
{
    my ($tokens_ref) = @_;
    
    my @list_of_surfaces_list = ();
    foreach my $token (@$tokens_ref) {
	if (defined $surfaceFormHashRef->{$token}) {
	    push(@list_of_surfaces_list, $surfaceFormHashRef->{$token});
	} else {
	    # surface form not found, use the word itself.
	    push(@list_of_surfaces_list, [$token]);
	    if ($wordSurfaceFormFile ne "None") {
		    print STDERR "Warning: no surface form for the word $token, use the word itself.\n";
	    }
	}
    }

    return &getCrossProductSurfaces_sub(0, "", \@list_of_surfaces_list);
}

# subroutine recursively called by getCrossProductSurfaces
# given one specific expansion of previous words in the sequence, expand all following words in the sequence to all possible surfaces
# arguments:
# 	- current word position: from which this subsequence expansion starts
# 	- prefix: one specific expansion of previous words
# 	- list of surfaces list (reference): the first dimension indexes the word in the original word sequence
# 					     the second dimension indexes the surface in the surface list of that word
# return:
# 	- (reference of) a list of cross product surface forms that start with the same given prefix.
sub getCrossProductSurfaces_sub
{
    my ($cur_word_pos, $prefix, $list_of_surfaces_list_ref) = @_;
    
    my @ret_surfaces = ();

    # sanity check
    if ($cur_word_pos == 0 && $prefix ne "") {
	die "Error: getCrossProductSurfaces_sub(): The prefix has to be empty string \"\" when current word position is 0.\n";
    }
    if ($cur_word_pos < 0 || $cur_word_pos > @$list_of_surfaces_list_ref) {
	die "Error: getCrossProductSurfaces_sub(): The current word position is out of bound.\n";
    }

    if ($cur_word_pos == @$list_of_surfaces_list_ref) {

	# end of recursion
	# since the current word position is the one after the last element in the word sequence,
	# the prefix would be one specific surface form expansion on the entire word squence.
	# So add the prefix to the return array

	if (defined $prefix && $prefix ne "") {
	    push(@ret_surfaces, $prefix);
	}
	return \@ret_surfaces;

    } else {
	
	my $cur_word_surfaces_ref = $list_of_surfaces_list_ref->[$cur_word_pos];

	for my $surfaces (@$cur_word_surfaces_ref) {
	    
	    # concatenate the current word surface with previous words expansions
	    my $newPrefix;
	    if ($cur_word_pos == 0) {
		$newPrefix = "$surfaces";
	    }
	    else {
		$newPrefix = "$prefix $surfaces";
	    }

	    # recursively expand following words
	    my $cross_product_surfaces_ref = &getCrossProductSurfaces_sub($cur_word_pos + 1, $newPrefix, $list_of_surfaces_list_ref);

	    push(@ret_surfaces, @$cross_product_surfaces_ref);
	}
	return \@ret_surfaces;

    }
}
