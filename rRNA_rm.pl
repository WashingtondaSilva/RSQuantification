#!/usr/bin/perl

=head

 Author: Yi Zheng
 update: 07/2/2013

=cut

use FindBin;
use IO::File;
use Getopt::Long;

my $usage = q'
USAGE:
Perl rRNA_rm.pl -i list_fasta 

  -s SequencingMethod (default = SS) 
  -r rRNA_database_index (default = /home/database/rRNA_silva111)
  -p number of CPU (default = 24)
  -v mismatch (default = 3) 
  -h help info

  SequencingMethod
  PE (paired-end);
  SE (single-end);
  PS (paired strand-specific);
  SS (single strand-specific);

  * the file in the list must has .fasta suffix, the output file has .fa suffix

';

my $help;
my ($read_list, $sequencing_method, $rRNA_index, $cpu, $mismatch);

GetOptions(
        "h|?|help"              => \$help,
        "i|list=s"              => \$read_list,
        "s|sequencing-method=s" => \$sequencing_method,
	"r|rRNA-index=s"	=> \$rRNA_index,
	"p|CPU=i"		=> \$cpu,
	"v|mismatch=i"		=> \$mismatch
);

die $usage if $help;
die $usage unless $read_list;
$rRNA_index ||= "/home/database/rRNA_silva111";
$sequencing_method ||= "SS";
$cpu ||= 24;
$mismatch ||= 3;

# check sequencing method
if ($sequencing_method ne "SE" && $sequencing_method ne "SS" && $sequencing_method ne "PE" && $sequencing_method ne "PS" ) {
        die "Error at sequencing-method: $sequencing_method\n";
}

# check list file
my %list_read = check_list_file($read_list, $sequencing_method);

# chec rRNA index file
my @index_files = (
        $rRNA_index.".1.ebwt",
        $rRNA_index.".2.ebwt",
        $rRNA_index.".3.ebwt",
        $rRNA_index.".4.ebwt",
        $rRNA_index.".rev.1.ebwt",
        $rRNA_index.".rev.2.ebwt"
);

foreach my $index_file (@index_files) {
        unless(-s $index_file) { die "Error! $index_file not exist or have no info\n"; }
}

# main
my $fh = IO::File->new($read_list) || die "Can not open list of fasta : $read_list $!\n";
while(<$fh>)
{
	chomp;
	# bowtie -v 3 -k 1 -p 10 --un E1-1.clean -f /home/feizj/bowtie_database/rRNA E1-1.fasta MMMM
	my $list = $_;
	my $cmd = "";

	if ($sequencing_method eq "SS" || $sequencing_method eq "SE")
	{
		my $read_file = $list_read{$list};
		if ($read_file =~ m/\.fasta/ )
		{
			my $out = $list.".fa";
			$cmd = "bowtie -v $mismatch -k 1 -p $cpu --un $out -f $rRNA_index $read_file MMMM";
		}
		elsif( $read_file =~ m/\.fastq/)
		{
			my $out = $list.".fq";
			$cmd = "bowtie -v $mismatch -k 1 -p $cpu --un $out $rRNA_index $read_file MMMM";
		}
		else { die "Error at input fasta for clean: $read_file\n"; }
	}
	else
	{
		my @read = split(/\t/, $list_read{$list});

		if ($read[0] =~ m/\.fasta/ && $read[1] =~ m/\.fasta/ )
		{
			$cmd = "bowtie -v $mismatch -k 1 -p $cpu --un $list -f $rRNA_index -1 $read[0] -2 $read[1] MMMM 2>&1";
		}
		elsif ($read[0] =~ m/\.fastq/ && $read[1] =~ m/\.fastq/)
		{
			$cmd = "bowtie -v $mismatch -k 1 -p $cpu --un $list $rRNA_index -1 $read[0] -2 $read[1] MMMM 2>&1";
		}
		else
		{
			die "Error at input fasta for clean: $read[0]\n";
		}
	}

	print $cmd."\n";
	system($cmd) && die "Error at $cmd\n";
}
$fh->close;
unlink("MMMM");

#################################################################
# kentnf: subroutine			 			#
#################################################################

=head1 Sub:check_list_file

=cut
sub check_list_file
{
        my ($list_file, $sequencing_method) = @_;
        my %list_info;
	my @file_surfix = (".fasta", ".fastq");
        #my @file_surfix = (".gz", ".fa", ".fa.gz", ".fasta", ".fasta.gz", ".fq", ".fq.gz", ".fastq", ".fastq.gz");

        my ($reads, $bams);
        my $ls = IO::File->new($list_file) || die "Can not open list file $list_file $!\n";
        while(my $list = <$ls>)
        {
                chomp($list);
                # check if the read files are exist
                if ($sequencing_method eq "PS" || $sequencing_method eq "PE")
                {
                        my $file1 = $list."_1";
                        my $file2 = $list."_2";
                        if (-s $file1 && -s $file2)
                        {
                                $reads = $file1."\t".$file2;
                        }
                        else
                        {
                                foreach my $surfix (@file_surfix)
                                {
                                        if (-s $file1.$surfix && -s $file2.$surfix)
                                        {
                                                $reads = $file1.$surfix."\t".$file2.$surfix;
                                        }
                                }
                        }
                }
                else
                {
                        if (-s $list)
                        {
                                $reads = $list;
                        }
                        else
                        {
                                foreach my $surfix (@file_surfix)
                                {
                                        if (-s $list.$surfix) {
                                                $reads = $list.$surfix;
                                        }
                                }
                        }
                }

                # put reads and bam to hash;
                if($reads )
                {
                        print STDERR "Locate file for list: $list.\nRead File: $reads;\n";
                        $list_info{$list} = $reads;
                }
                else
                {
                        print STDERR "Error! Can not locate read or BAM for list: $list.\n";
                }
        }
        $ls->close;
        return %list_info;
}
