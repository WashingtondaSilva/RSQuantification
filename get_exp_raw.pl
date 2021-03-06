#!/usr/bin/perl

=head1 Name

 get_exp_raw.pl

=head1 Version

 Author:  Yi Zheng
 Version: 1.0

=head1 Update
 
 2013-05-19
 1. output the mapping reads to with fasta format like:
 >read_id-geneid  Info
 sequence

 2012-08-15
 1. Fix a bug for count SE reads

 2012-03-06
 1. remove the 'sense' and 'antisense' suffix from sample name of output file

 2012-03-09
 1. using Getopt::Long modular

=head1 Description

 -i|list    		(str)  	input read list file (required)
 -a|gene-position	(str)	gene position file (required)
 -o|output              (str)  	prefix of out files (default = exp; exp_sense_raw, exp_antisense_raw)
 -s|sequencing-method   (str)  	(required) (default = SS)
	PE (paired-end); 
	SE (single-end); 
	PS (paired strand-specific); 
	SS (single strand-specific);
 -d				output the mapping reads with corresponding gene
 -h|?|help                help info

 =========================================
 gene and position format:
 chr  start  end  gene  strand
 =========================================

=head1 Example

 Perl get_exp_raw.pl -i read_list -s SS -a tomato_gene_position

=cut
use strict;
use warnings;
use IO::File;
use Getopt::Long;

my $help;
my ($read_list, $sequencing_method, $gene_pos, $detail_mapping, $output);

GetOptions(
	"h|?|help"		=> \$help,
	"i|list=s"		=> \$read_list,
	"s|sequencing-method=s"	=> \$sequencing_method,
	"a|gene-position=s"	=> \$gene_pos,
	"d|detail-mapping"	=> \$detail_mapping,
	"o|output=s"		=> \$output
);

die `pod2text $0` if $help;
die `pod2text $0` unless $read_list;

$output ||= "exp";
$sequencing_method ||= "SS";
$detail_mapping ||= 0;

# check sequencing method
if ($sequencing_method ne "SE" && $sequencing_method ne "SS" && $sequencing_method ne "PE" && $sequencing_method ne "PS" ) {
        die "Error at sequencing-method: $sequencing_method\n";
}
my $sequencing = $sequencing_method;

# check files base on sequencing 
my $list = IO::File->new($read_list) || die "Can not open read file $read_list\n";
while(<$list>)
{
	chomp;
	
	if ($sequencing eq "PS" || $sequencing eq "SS")
	{
		my $plus_bam = $_."_plus.bam";
		my $minus_bam = $_."_minus.bam";
		unless(-s $plus_bam ) { die "File $plus_bam do not exist\n"; }
		unless(-s $minus_bam ) { die "File $minus_bam do not exist\n"; }
	}
	elsif ($sequencing eq "PE" || $sequencing eq "SE")
	{
		my $bam = $_."_all.bam";
		unless(-s $bam ) { die "File $bam do not exist\n"; }
	}
	else
	{
		die "Error at sequencing method 1: $sequencing\n";
	}
}
$list->close;

#################################################################
# load gene position info to hash				#
#################################################################
my %pos_hash;	# position and genes;
my %trans; 	# trans id and strand;

my $gfh = IO::File->new($gene_pos) || die "Can not open gene position file $gene_pos\n";
while(<$gfh>)
{
	chomp;
	my @a = split(/\t/, $_);

	# chr		start	end	GeneID			Strand
	# SL2.40ch00	16437	18189	Solyc00g005000.2.1	+
	for(my $i = $a[1]; $i<=$a[2]; $i++)
	{
		if (defined $pos_hash{$a[0]."#".$i})
		{
			$pos_hash{$a[0]."#".$i}.= "\t".$a[3];
		}
		else
		{
			$pos_hash{$a[0]."#".$i} = $a[3];
		}
	}
	$trans{$a[3]} = $a[4];
}
$gfh->close;

#################################################################
# main								#
#################################################################
my %all_count = ();
my %sense_count = ();
my %antisense_count = ();
my %g_count = ();
my @read_files = ();

my $fh = IO::File->new($read_list) || die "Can not open read list file $read_list\n";
while(<$fh>)
{
	chomp;

	push(@read_files, $_);

	if ($sequencing eq "PS" || $sequencing eq "SS")
	{
		# convert bam to sam
		my $plus_bam = $_."_plus.bam";
		my $minus_bam = $_."_minus.bam";
		my $plus_sam = $_."_plus.sam";
		my $minus_sam = $_."_minus.sam";
		system("samtools view -h -o $plus_sam $plus_bam") && die "Error at samtools view -h -o $plus_sam $plus_bam\n";
		system("samtools view -h -o $minus_sam $minus_bam") && die "Error at samtools view -h -o $minus_sam $minus_bam\n";

		# count read num for each gene
		my %plus_gene_count; my %minus_gene_count;

		if ($sequencing eq "SS")
		{
			%plus_gene_count  = count_mapped_gene_single($plus_sam,  $detail_mapping);
			%minus_gene_count = count_mapped_gene_single($minus_sam, $detail_mapping);
		}
		else
		{
			%plus_gene_count  = count_mapped_gene_paired($plus_sam,  $detail_mapping);
			%minus_gene_count = count_mapped_gene_paired($minus_sam, $detail_mapping);
		}

		# convert plus and minus to sense and antisense; and store info to hash
	        foreach my $trans (sort keys %trans)
		{
 			my $strand = $trans{$trans};

			if ( defined $plus_gene_count{$trans} || defined $minus_gene_count{$trans} )
                	{
                        	unless (defined $plus_gene_count{$trans}) { $plus_gene_count{$trans} = 0; }
                        	unless (defined $minus_gene_count{$trans}) { $minus_gene_count{$trans} = 0; }

				my ($antisense_num, $sense_num);
                        	if      ($strand eq "+") { $antisense_num = $plus_gene_count{$trans};  $sense_num = $minus_gene_count{$trans}; }
                        	elsif   ($strand eq "-") { $antisense_num = $minus_gene_count{$trans}; $sense_num = $plus_gene_count{$trans};  }
                        	else    {die "Error at strand in : $trans\n";  }

                        	$sense_count{$trans}.= "\t".$sense_num;
				$antisense_count{$trans}.= "\t".$antisense_num;
                	}
                	else
                	{
				$sense_count{$trans}.= "\t0";
				$antisense_count{$trans}.= "\t0";
                	}
		}
		unlink($plus_sam);
		unlink($minus_sam);
	}
	elsif ($sequencing eq "PE" || $sequencing eq "SE")
        {
		# convert bam to sam
                my $bam = $_."_all.bam";
		my $sam = $_."_all.sam";
		system("samtools view -h -o $sam $bam") && die "Error at samtools view -h -o $sam $bam\n";

		# count read num for each gene
		if ($sequencing eq "SE")
		{
			%g_count = count_mapped_gene_single($sam, $detail_mapping);
		}
		else
		{
			%g_count = count_mapped_gene_paired($sam, $detail_mapping);
		}

		# store info to hash
		foreach my $trans (sort keys %trans)
		{
			my $strand = $trans{$trans};
			if ( defined $g_count{$trans})
			{
				$all_count{$trans}.= "\t".$g_count{$trans};
			}
			else
			{
				$all_count{$trans}.= "\t0";
			}
		}
		unlink($sam);
	}
	else
	{
		die "Error at sequencing method 2: $sequencing\n";
	}
}
$fh->close;

#################################################################
# output result							#
#################################################################
if ($sequencing eq "SS" || $sequencing eq "PS")
{
	my $output_sense 	= $output."_sense_raw"; 
	my $output_antisense	= $output."_antisense_raw";

	my $fs = IO::File->new(">".$output_sense)     || die "Can not open file expression_raw_sense : $output_sense\n";
	my $fa = IO::File->new(">".$output_antisense) || die "Can not open file expression_raw_antisense : $output_antisense\n";

	# output header
	print $fs "gene"; 
	print $fa "gene";

	foreach my $file (@read_files)
	{
		print $fs "\t$file";
		print $fa "\t$file";
	}
	print $fs "\n";
	print $fa "\n";

	# output raw count for sense
	foreach my $trans ( sort keys %trans )
	{
		my @a = split(/\t/, $sense_count{$trans});
		print $fs $trans.$sense_count{$trans}."\n";

		my @b = split(/\t/, $antisense_count{$trans});
		print $fa $trans.$antisense_count{$trans}."\n";
	}
	$fs->close;
	$fa->close;
}
elsif ($sequencing eq "SE" || $sequencing eq "PE")
{
	my $output_all = $output."_all";
	my $fr = IO::File->new(">".$output_all) || die "Can not open file expression_raw_sense : $output_all\n";

	# output header
        print $fr "gene";

        foreach my $file (@read_files)
        {
		print $fr "\t$file";
        }
        print $fr "\n";

	foreach my $trans ( sort keys %trans )
	{
		#print $trans."\n"; die;
		my @a = split(/\t/, $all_count{$trans});
		print $fr $trans.$all_count{$trans}."\n";
	}
	$fr->close;
}
else
{
	die "Error at sequencing method 3: $sequencing\n";
}
#################################################################
# kentnf: subroutine						#
#################################################################

=head1 Sub:count_mapped_gene_single

=cut
sub count_mapped_gene_single
{
	my ($sam_file, $detail_mapping) = @_;
	
	my $read_mapped_fasta = $sam_file;
	$read_mapped_fasta =~ s/\.sam/_mapped\.fa/;

	# stroe the sam info to hash
	my %single_read = ();
	my %read_seq = ();

        my $fhs = IO::File->new($sam_file) || die "Can not open sam file $sam_file\n";
        while(<$fhs>)
        {
                chomp;
                my @a = split(/\t/, $_);

                # MCIC-SOLEXA_0001:2:44:16153:10598#0     99      SL2.40ch00      100512  255     76M     =       100557  121     CTACTTTGTTCTTATGGAAAAATACTCAATAGTAAAGAAGTTAAAATTTCGAGCGACCAATTGAATGGGTTTCTGT fffffffffffffffffffffffffffffffffffffdffffffffffeefffefffffdUKUZWca_a^fdeffc    NM:i:0  NH:i:1
                unless ($_ =~ m/^@/)
                {
			my $length = parse_cigar($a[5]);
                        my $read_end = $a[3] + $length - 1;
                        my $key_info = $a[0]."\t".$a[2]."\t".$a[3]."\t".$read_end;

			if ($detail_mapping) { $read_seq{$a[0]} = $a[9]; }

                        if (defined $single_read{$key_info} ) { $single_read{$key_info}++; }
                        else { $single_read{$key_info} = 1; }
                }
        }
        $fhs->close;

	# count the number of mapped read for gene using single read hash
	# output the mapped reads info to fasta sequence file
	my $out;
	if ($detail_mapping) {
		$out = IO::File->new(">".$read_mapped_fasta) || die "Can not open read mapped fasta file: $read_mapped_fasta $!\n";
	}
	my %gene_count;

	foreach my $read (sort keys %single_read)
        {
                my @a = split(/\t/, $read);

                my $start = $a[1]."#".$a[2];
                my $end = $a[1]."#".$a[3];
                my $num = $single_read{$read}; 

		# two read has same key info: read id, ref id, start and stop are same. may impossible
		my @genes;
                if (defined $pos_hash{$start} && defined $pos_hash{$end} )
                {
                        if ( $pos_hash{$start} eq $pos_hash{$end} ) 
			{ 
				@genes = split(/\t/, $pos_hash{$start}); 
			}
                        else
                        {
				my @genes1 = split(/\t/, $pos_hash{$start});
				my @genes2 = split(/\t/, $pos_hash{$end});
				my %gene;
				foreach my $g1 (@genes1) { $gene{$g1} = 1; }
				foreach my $g2 (@genes2) { $gene{$g2} = 1; }
				@genes = keys(%gene);
                        }
                }
                elsif ( defined $pos_hash{$start} )
                {
			@genes = split(/\t/, $pos_hash{$start});
                }
                elsif ( defined $pos_hash{$end})
                {
			@genes = split(/\t/, $pos_hash{$end});
                }
                else
                {
			@genes = ();
                }

		# count the read number for each gene
		foreach my $gene (sort @genes) 
		{
			if (defined $gene_count{$gene}) { $gene_count{$gene}++; }
			else { $gene_count{$gene}=1; }
		}

		# output the mapped reads with corresponding genes
		if ($detail_mapping)
		{
			if (scalar(@genes) > 0)
			{
				my $gene = join("#", @genes);
				print $out ">".$a[0]."-$gene\t$a[1]:$a[2]-$a[3]\n".$read_seq{$a[0]}."\n";
			}
			else
			{
				print $out ">".$a[0]."-Intergenic\t$a[1]:$a[2]-$a[3]\n".$read_seq{$a[0]}."\n";
			}
		}
        }

	if ($detail_mapping) { $out->close; }

	return %gene_count;
}

=head1 Sub:count_mapped_gene_paired

=cut
sub count_mapped_gene_paired
{
	my ($sam_file, $detail_mapping) = @_;

	my $read_mapped_fasta1 = $sam_file;
	my $read_mapped_fasta2 = $sam_file;
	$read_mapped_fasta1 =~ s/\.sam/_mapped_1\.fa/;
	$read_mapped_fasta2 =~ s/\.sam/_mapped_2\.fa/;	

	# stroe the sam info to hash
        my %pair_read = ();
	my %read_seq = ();

	my $fhs = IO::File->new($sam_file) || die "Can not open sam file $sam_file\n";
	while(<$fhs>)
	{
		chomp;
		my @a = split(/\t/, $_);

		# MCIC-SOLEXA_0001:2:44:16153:10598#0     99      SL2.40ch00      100512  255     76M     =       100557  121     CTACTTTGTTCTTATGGAAAAATACTCAATAGTAAAGAAGTTAAAATTTCGAGCGACCAATTGAATGGGTTTCTGT fffffffffffffffffffffffffffffffffffffdffffffffffeefffefffffdUKUZWca_a^fdeffc    NM:i:0  NH:i:1
		unless ($_ =~ m/^@/)
		{
			my $key_info;
			if ($a[6] eq '=') { $a[6] = $a[2]; }
			if ($a[3] < $a[7])	{ $key_info = $a[0]."\t".$a[2]."\t".$a[3]."\t".$a[6]."\t".$a[7]; }
			elsif ($a[3] > $a[7])	{ $key_info = $a[0]."\t".$a[6]."\t".$a[7]."\t".$a[2]."\t".$a[3]; }
			else			{ $key_info = $a[0]."\t".$a[6]."\t".$a[7]."\t".$a[2]."\t".$a[3]; }
			$pair_read{$key_info} = 1;

			if ($detail_mapping) {
				my $seq_key = $a[0]."\t".$a[2]."\t".$a[3];
				$read_seq{$seq_key} = $a[9];
			}
		}
	}
	$fhs->close;

	# get the number of read mapped to each genes
	# output the mapped reads info to fasta sequence file
	my ($out1, $out2);
	if ($detail_mapping) 
	{
		$out1 = IO::File->new(">".$read_mapped_fasta1) || die "Can not open read mapped fasta file: $read_mapped_fasta1 $!\n";
		$out2 = IO::File->new(">".$read_mapped_fasta2) || die "Can not open read mapped fasta file: $read_mapped_fasta2 $!\n";
	}
	my %gene_count = ();

	foreach my $read (sort keys %pair_read)
	{
		my @a = split(/\t/, $read);
		
		my $start = $a[1]."#".$a[2];
		my $end = $a[3]."#".$a[4];

		my ($key1, $key2);
		$key1 = $a[0]."\t".$a[1]."\t".$a[2];
		$key2 = $a[0]."\t".$a[3]."\t".$a[4];

		my @genes;
		if (defined $pos_hash{$start} && defined $pos_hash{$end} )
		{
			if ( $pos_hash{$start} eq $pos_hash{$end} )
			{
				@genes = split(/\t/, $pos_hash{$start});
			}
			else
			{
				my @genes1 = split(/\t/, $pos_hash{$start});
				my @genes2 = split(/\t/, $pos_hash{$end});
				my %gene;
				foreach my $g1 (@genes1) { $gene{$g1} = 1; }
				foreach my $g2 (@genes2) { $gene{$g2} = 1; }
				@genes = keys(%gene);
			}
		}
		elsif ( defined $pos_hash{$start} )
		{
			@genes = split(/\t/, $pos_hash{$start});
		}
		elsif ( defined $pos_hash{$end})
		{
			@genes = split(/\t/, $pos_hash{$end});
		}
		else
		{
			@genes = ();
		}
		
		# count the number of reads for each gene
		foreach my $gene (sort @genes)
		{
			if (defined $gene_count{$gene}) { $gene_count{$gene}++; }
			else { $gene_count{$gene}=1; }
		}
		
		# output the mapped reads with corresponding genes
		if ($detail_mapping)
		{	
			if (scalar(@genes) > 0)
			{
				my $gene = join("#", @genes);
				print $out1 ">".$a[0]."-$gene\t$a[1]:$a[2]-$a[3]:$a[4]\n".$read_seq{$key1}."\n";
				print $out2 ">".$a[0]."-$gene\t$a[1]:$a[2]-$a[3]:$a[4]\n".$read_seq{$key2}."\n";
			}
			else
			{
				print $out1 ">".$a[0]."-Intergenic\t$a[1]:$a[2]-$a[3]:$a[4]\n".$read_seq{$key1}."\n";
				print $out2 ">".$a[0]."-Intergenic\t$a[1]:$a[2]-$a[3]:$a[4]\n".$read_seq{$key2}."\n";
			}
		}
	}

	if ($detail_mapping) { $out1->close; $out2->close; }
	return %gene_count;
}



=head1 Sub:parse cigar

=cut
sub parse_cigar
{
	my $cigar = shift;

	my $str_len = length($cigar);

	my $num = "";; my $mapped_length = 0;

	for(my $i=0; $i<$str_len; $i++)
	{
		my $str = substr($cigar, $i, 1);

		if ($str =~ m/\d+/)
		{
			$num = $num.$str;
		}
		elsif ($str eq "M" || $str eq "N" || $str eq "I")
		{
			$mapped_length = $mapped_length + $num;
			$num = "";
			
		}
		elsif ($str eq "D") 
		{
			$num = "";
		}
	}

	return $mapped_length;
}
