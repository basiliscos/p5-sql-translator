#!/usr/bin/perl

# $Id: auto-dia.pl,v 1.8 2003-04-03 19:29:08 kycl4rk Exp $

=head1 NAME 

auto-dia.pl - Automatically create a diagram from a database schema

=head1 SYNOPSIS

  ./auto-dia.pl -d|--db=db_parser [options] schema.sql

  Options:

    -o|--output        Output file name (default STDOUT)
    -i|--image         Output image type ("png" or "jpeg," default "png")
    -t|--title         Title to give schema
    -c|--cols          Number of columns
    -n|--no-lines      Don't draw lines
    -f|--font-size     Font size ("small," "medium," "large," or "huge,"
                       default "medium")
    --color            Add colors
    --show-fk-only     Only show fields that act as primary 
                       or foreign keys

    --natural-join     Perform natural joins
    --natural-join-pk  Perform natural joins from primary keys only
    -s|--skip          Fields to skip in natural joins
    --debug            Print debugging information

=head1 DESCRIPTION

This script will create a picture of your schema.  Only the database
driver argument (for SQL::Translator) is required.  If no output file
name is given, then image will be printed to STDOUT, so you should
redirect the output into a file.

The default action is to assume the presence of foreign key
relationships defined via "REFERNCES" or "FOREIGN KEY" constraints on
the tables.  If you are parsing the schema of a file that does not
have these, you will find the natural join options helpful.  With
natural joins, like-named fields will be considered foreign keys.
This can prove too permissive, however, as you probably don't want a
field called "name" to be considered a foreign key, so you could
include it in the "skip" option, and all fields called "name" will be
excluded from natural joins.  A more efficient method, however, might
be to simply deduce the foriegn keys from primary keys to other fields
named the same in other tables.  Use the "natural-join-pk" option
to acheive this.

=cut

use strict;
use Data::Dumper;
use Getopt::Long;
use GD;
use Pod::Usage;
use SQL::Translator;

my $VERSION = (qw$Revision: 1.8 $)[-1];

use constant VALID_FONT_SIZE => {
    small  => 1,
    medium => 1,
    large  => 1,
    huge   => 1,
};

use constant VALID_IMAGE_TYPE => {
    png  => 1, 
    jpeg => 1, 
};

#
# Get arguments.
#
my ( 
    $out_file, $image_type, $db_driver, $title, $no_columns, 
    $no_lines, $font_size, $add_color, $debug, $show_fk_only,
    $natural_join, $join_pk_only, $skip_fields
);

GetOptions(
    'd|db=s'          => \$db_driver,
    'o|output:s'      => \$out_file,
    'i|image:s'       => \$image_type,
    't|title:s'       => \$title,
    'c|columns:i'     => \$no_columns,
    'n|no-lines'      => \$no_lines,
    'f|font-size:s'   => \$font_size,
    'color'           => \$add_color,
    'show-fk-only'    => \$show_fk_only,
    'natural-join'    => \$natural_join,
    'natural-join-pk' => \$join_pk_only,
    's|skip:s'        => \$skip_fields,
    'debug'           => \$debug,
) or die pod2usage;
my $file = shift @ARGV or pod2usage( -message => 'No input file' );

pod2usage( -message => "No db driver specified" ) unless $db_driver;
$title        ||= $file;
$image_type     = 'png'    unless VALID_IMAGE_TYPE ->{ $image_type  };
$font_size      = 'medium' unless VALID_FONT_SIZE->{ $font_size };
my %skip        = map { $_, 1 } split ( /,/, $skip_fields );
$natural_join ||= $join_pk_only;

#
# Parse file.
#
warn "Parsing file '$file' with driver '$db_driver'\n" if $debug;
my $t    = SQL::Translator->new( parser => $db_driver, producer => 'Raw' );
my $data = $t->translate( $file ) or die $t->error;
warn "Data =\n", Dumper( $data ), "\n" if $debug;

#
# Layout the image.
#
my $font         = 
    $font_size eq 'small'  ? gdTinyFont  :
    $font_size eq 'medium' ? gdSmallFont :
    $font_size eq 'large'  ? gdLargeFont : gdGiantFont;
my $no_tables    = scalar keys %$data;
$no_columns    ||= sprintf( "%.0f", sqrt( $no_tables ) + .5 );
$no_columns    ||= .5;
my $no_per_col   = sprintf( "%.0f", $no_tables/$no_columns + .5 );

my @shapes;            
my ( $max_x, $max_y );           # the furthest x and y used
my $orig_y      = 40;            # used to reset y for each column
my ( $x, $y )   = (30, $orig_y); # where to start
my $cur_col     = 1;             # the current column
my $no_this_col = 0;             # number of tables in current column
my $this_col_x  = $x;            # current column's x
my $gutter      = 30;            # distance b/w columns
my %nj_registry;                 # for locations of fields for natural joins
my @fk_registry;                 # for locations of fields for foreign keys
my %table_x;                     # for max x of each table
my $field_no;                    # counter to give distinct no. to each field
my %legend;

#
# If necessary, pre-process fields to find foreign keys.
#
if ( $show_fk_only && $natural_join ) {
    my ( %common_keys, %pk );
    for my $table ( values %$data ) {
        for my $index ( 
            @{ $table->{'indices'}     || [] },
            @{ $table->{'constraints'} || [] },
        ) {
            my @fields = @{ $index->{'fields'} || [] } or next;
            if ( $index->{'type'} eq 'primary_key' ) {
                $pk{ $_ } = 1 for @fields;
            }
        }

        for my $field ( values %{ $table->{'fields'} } ) {
            push @{ $common_keys{ $field->{'name'} } }, $table->{'table_name'};
        }
    }

    for my $field ( keys %common_keys ) {
        my @tables = @{ $common_keys{ $field } };
        next unless scalar @tables > 1;
        for my $table ( @tables ) {
            next if $join_pk_only and !defined $pk{ $field };
            $data->{ $table }{'fields'}{ $field }{'is_fk'} = 1;
        }
    }
}
else {
    for my $table ( values %$data ) {
        for my $field ( values %{ $table->{'fields'} } ) {
            for my $constraint ( 
                grep { $_->{'type'} eq 'foreign_key' }
                @{ $field->{'constraints'} }
            ) {
                my $ref_table  = $constraint->{'reference_table'} or next;
                for my $ref_field ( @{ $constraint->{'reference_fields'} } ) {
                    $data->{ $ref_table }{'fields'}{ $ref_field }{'is_fk'} = 1;
                }
            }
        }
    }
}

for my $table (
    map  { $_->[1] }
    sort { $a->[0] <=> $b->[0] }
    map  { [ $_->{'order'}, $_ ] }
    values %$data 
) {
    my $table_name = $table->{'table_name'};
    my $top        = $y;
    push @shapes, [ 'string', $font, $this_col_x, $y, $table_name, 'black' ];

    $y                   += $font->height + 2;
    my $below_table_name  = $y;
    $y                   += 2;
    my $this_max_x        = $this_col_x + ($font->width * length($table_name));

    warn "Processing table '$table_name'\n" if $debug;

    my @fields = 
        map  { $_->[1] }
        sort { $a->[0] <=> $b->[0] }
        map  { [ $_->{'order'}, $_ ] }
        values %{ $table->{'fields'} };

    warn "Fields = ", join(', ', map { $_->{'name'} } @fields), "\n" if $debug;

    my ( %pk, %unique );
    for my $index ( 
        @{ $table->{'indices'}     || [] },
        @{ $table->{'constraints'} || [] },
    ) {
        my @fields = @{ $index->{'fields'} || [] } or next;
        if ( $index->{'type'} eq 'primary_key' ) {
            $pk{ $_ } = 1 for @fields;
        }
        elsif ( $index->{'type'} eq 'unique' ) {
            $unique{ $_ } = 1 for @fields;
        }
    }

    warn "Primary keys = ", join(', ', sort keys %pk), "\n" if $debug;
    warn "Unique = ", join(', ', sort keys %unique), "\n" if $debug;

    my ( @fld_desc, $max_name );
    for my $f ( @fields ) {
        my $name      = $f->{'name'} or next;
        my $is_pk     = $pk{ $name };
        my $is_unique = $unique{ $name };

        #
        # Decide if we should skip this field.
        #
        if ( $show_fk_only ) {
            if ( $natural_join ) {
                next unless $is_pk || $f->{'is_fk'};
            }
            else {
                next unless $is_pk || $f->{'is_fk'} || 
                    grep { $_->{'type'} eq 'foreign_key' }
                    @{ $f->{'constraints'} }
                ;
            }
        }

        if ( $is_pk ) {
            $name .= ' *';
            $legend{'Primary key'} = '*';
        }
        elsif ( $is_unique ) {
            $name .= ' [U]';
            $legend{'Unique constraint'} = '[U]';
        }

        my $size = @{ $f->{'size'} || [] } 
            ? '(' . join( ',', @{ $f->{'size'} } ) . ')'
            : '';
        my $desc = join( ' ', map { $_ || () } $f->{'data_type'}, $size );
        
        my $nlen  = length $name;
        $max_name = $nlen if $nlen > $max_name;
        push @fld_desc, [ $name, $desc, $f->{'name'}, $is_pk ];
    }

    $max_name += 4;
    for my $fld_desc ( @fld_desc ) {
        my ( $name, $desc, $orig_name, $is_pk ) = @$fld_desc;
        my $diff = $max_name - length $name;
        $name   .= ' ' x $diff;
        $desc    = $name . $desc;

        push @shapes, [ 'string', $font, $this_col_x, $y, $desc, 'black' ];
        $y         += $font->height + 2;
        my $length  = $this_col_x + ( $font->width * length( $desc ) );
        $this_max_x = $length if $length > $this_max_x;

        my $constraints = $table->{'fields'}{ $orig_name }{'constraints'};

        if ( $natural_join && !$skip{ $orig_name } ) {
            push @{ $nj_registry{ $orig_name } }, $table_name;
        }
        elsif ( @{ $constraints || [] } ) {
            for my $constraint ( @$constraints ) {
                next unless $constraint->{'type'} eq 'foreign_key';
                for my $fk_field ( 
                    @{ $constraint->{'reference_fields'} || [] }
                ) {
                    my $fk_table = $constraint->{'reference_table'};
                    next unless defined $data->{ $fk_table };
                    push @fk_registry, [
                        [ $table_name, $orig_name ],
                        [ $fk_table  , $fk_field  ],
                    ];
                }
            }
        }

        my $y_link = $y - $font->height/2;
        $table->{'fields'}{ $orig_name }{'coords'} = {
            left     => [ $this_col_x - 6, $y_link ],
            right    => [ $length + 2    , $y_link ],
            table    => $table_name,
            field_no => ++$field_no,
            is_pk    => $is_pk,
            fld_name => $orig_name,
        };
    }

    $this_max_x += 5;
    $table_x{ $table_name } = $this_max_x + 5;
    push @shapes, [ 'line', $this_col_x - 5, $below_table_name, 
        $this_max_x, $below_table_name, 'black' ];
    my @bounds = ( $this_col_x - 5, $top - 5, $this_max_x, $y + 5 );
    if ( $add_color ) {
        unshift @shapes, [ 
            'filledRectangle', 
            $bounds[0], $bounds[1],
            $this_max_x, $below_table_name,
            'khaki' 
        ];
        unshift @shapes, [ 'filledRectangle', @bounds, 'white' ];
    }
    push @shapes, [ 'rectangle', @bounds, 'black' ];
    $max_x = $this_max_x if $this_max_x > $max_x;
    $y    += 25;
    
    if ( ++$no_this_col == $no_per_col ) { # if we've filled up this column
        $cur_col++;                        # up the column number
        $no_this_col = 0;                  # reset the number of tables
        $max_x      += $gutter;            # push the x over for next column
        $this_col_x  = $max_x;             # remember the max x for this column
        $max_y       = $y if $y > $max_y;  # note the max y
        $y           = $orig_y;            # reset the y for next column
    }
}

#
# Connect the lines.
#
my %horz_taken;
my %done;
unless ( $no_lines ) {
    my @position_bunches;

    if ( $natural_join ) {
        for my $field_name ( keys %nj_registry ) {
            my @positions;
            my @table_names = @{ $nj_registry{ $field_name } || [] } or next;
            next if scalar @table_names == 1;

            for my $table_name ( @table_names ) {
                push @positions,
                    $data->{ $table_name }{'fields'}{ $field_name }{'coords'};
            }

            push @position_bunches, [ @positions ];
        }
    }
    else {
        for my $pair ( @fk_registry ) {
            push @position_bunches, [ 
                $data->{ $pair->[0][0] }{'fields'}{ $pair->[0][1] }{'coords'},
                $data->{ $pair->[1][0] }{'fields'}{ $pair->[1][1] }{'coords'},
            ];
        }
    }

    my $is_directed = $natural_join ? 0 : 1;

    for my $bunch ( @position_bunches ) {
        my @positions = @$bunch;

        for my $i ( 0 .. $#positions ) {
            my $pos1        = $positions[ $i ];
            my ( $ax, $ay ) = @{ $pos1->{'left'}  || [] } or next;
            my ( $bx, $by ) = @{ $pos1->{'right'} || [] } or next;
            my $table1      = $pos1->{'table'};
            my $fno1        = $pos1->{'field_no'};
            my $is_pk       = $pos1->{'is_pk'};
            next if $join_pk_only and !$is_pk;

            for my $j ( 0 .. $#positions ) {
                my $pos2        = $positions[ $j ];
                my ( $cx, $cy ) = @{ $pos2->{'left'}  || [] } or next;
                my ( $dx, $dy ) = @{ $pos2->{'right'} || [] } or next;
                my $table2      = $pos2->{'table'};
                my $fno2        = $pos2->{'field_no'};
                next if $table1 eq $table2;
                next if $done{ $fno1 }{ $fno2 };
                next if $fno1 == $fno2;

                my @distances = ();
                push @distances, [
                    abs ( $ax - $cx ) + abs ( $ay - $cy ),
                    [ $ax, $ay, $cx, $cy ],
                    [ 'left', 'left' ]
                ];
                push @distances, [
                    abs ( $ax - $dx ) + abs ( $ay - $dy ),
                    [ $ax, $ay, $dx, $dy ],
                    [ 'left', 'right' ],
                ];
                push @distances, [
                    abs ( $bx - $cx ) + abs ( $by - $cy ),
                    [ $bx, $by, $cx, $cy ],
                    [ 'right', 'left' ],
                ];
                push @distances, [
                    abs ( $bx - $dx ) + abs ( $by - $dy ),
                    [ $bx, $by, $dx, $dy ],
                    [ 'right', 'right' ],
                ];
                @distances   = sort { $a->[0] <=> $b->[0] } @distances;
                my $shortest = $distances[0];
                my ( $x1, $y1, $x2, $y2 ) = @{ $shortest->[1] };
                my ( $side1, $side2     ) = @{ $shortest->[2] };
                my ( $start, $end );
                my $offset     = 9;
                my $col1_right = $table_x{ $table1 };
                my $col2_right = $table_x{ $table2 };

                my $diff = 0;
                if ( $x1 == $x2 ) {
                    while ( $horz_taken{ $x1 + $diff } ) {
                        $diff = $side1 eq 'left' ? $diff - 2 : $diff + 2; 
                    }
                    $horz_taken{ $x1 + $diff } = 1;
                }

                if ( $side1 eq 'left' ) {
                    $start = $x1 - $offset + $diff;
                }
                else {
                    $start = $col1_right + $diff;
                }

                if ( $side2 eq 'left' ) {
                    $end = $x2 - $offset + $diff;
                } 
                else {
                    $end = $col2_right + $diff;
                } 

                push @shapes, [ 'line', $x1,    $y1, $start, $y1, 'cadetblue' ];
                push @shapes, [ 'line', $start, $y1, $end,   $y2, 'cadetblue' ];
                push @shapes, [ 'line', $end,   $y2, $x2,    $y2, 'cadetblue' ];

                if ( $is_directed ) {
                    if (
                        $side1 eq 'right' && $side2 eq 'left'
                        ||
                        $side1 eq 'left' && $side2 eq 'left'
                    ) {
                        push @shapes, [ 
                            'line', $x2 - 3, $y2 - 3, $x2, $y2, 'cadetblue' 
                        ];
                        push @shapes, [ 
                            'line', $x2 - 3, $y2 + 3, $x2, $y2, 'cadetblue' 
                        ];
                        push @shapes, [ 
                            'line', $x2 - 3, $y2 - 3, $x2 - 3, $y2 +3, 
                            'cadetblue' 
                        ];
                    }
                    else {
                        push @shapes, [ 
                            'line', $x2 + 3, $y2 - 3, $x2, $y2, 'cadetblue' 
                        ];
                        push @shapes, [ 
                            'line', $x2 + 3, $y2 + 3, $x2, $y2, 'cadetblue' 
                        ];
                        push @shapes, [ 
                            'line', $x2 + 3, $y2 - 3, $x2 + 3, $y2 +3, 
                            'cadetblue' 
                        ];
                    }
                }

                $done{ $fno1 }{ $fno2 } = 1;
                $done{ $fno2 }{ $fno1 } = 1;
            }
        }
    }
}

#
# Add the title, legend and signature.
#
my $large_font = gdLargeFont;
my $title_len  = $large_font->width * length $title;
push @shapes, [ 
    'string', $large_font, $max_x/2 - $title_len/2, 10, $title, 'black' 
];

if ( %legend ) {
    $max_y += 5;
    push @shapes, [ 
        'string', $font, $x, $max_y - $font->height - 4, 'Legend', 'black'
    ];
    $max_y += $font->height + 4;

    my $longest;
    for my $len ( map { length $_ } values %legend ) {
        $longest = $len if $len > $longest; 
    }
    $longest += 2;

    while ( my ( $key, $shape ) = each %legend ) {
        my $space = $longest - length $shape;
        push @shapes, [ 
            'string', $font, $x, $max_y - $font->height - 4, 
            join( '', $shape, ' ' x $space, $key ), 'black'
        ];

        $max_y += $font->height + 4;
    }
}

my $sig     = "auto-dia.pl $VERSION";
my $sig_len = $font->width * length $sig;
push @shapes, [ 
    'string', $font, $max_x - $sig_len, $max_y - $font->height - 4, 
    $sig, 'black'
];

#
# Render the image.
#
my $gd = GD::Image->new( $max_x + 30, $max_y );
unless ( $gd->can( $image_type ) ) {
    die "GD can't create images of type '$image_type'\n";
}
my %colors = map { $_->[0], $gd->colorAllocate( @{$_->[1]} ) } (
    [ white                => [ 255, 255, 255 ] ],
    [ beige                => [ 245, 245, 220 ] ],
    [ black                => [   0,   0,   0 ] ],
    [ lightblue            => [ 173, 216, 230 ] ],
    [ cadetblue            => [  95, 158, 160 ] ],
    [ lightgoldenrodyellow => [ 250, 250, 210 ] ],
    [ khaki                => [ 240, 230, 140 ] ],
    [ red                  => [ 255,   0,   0 ] ],
);
$gd->interlaced( 'true' );
my $background_color = $add_color ? 'lightgoldenrodyellow' : 'white';
$gd->fill( 0, 0, $colors{ $background_color } );
for my $shape ( @shapes ) {
    my $method = shift @$shape;
    my $color  = pop   @$shape;
    $gd->$method( @$shape, $colors{ $color } );
}

#
# Print the image.
#
if ( $out_file ) {
    open my $fh, ">$out_file" or die "Can't write '$out_file': $!\n";
    print $fh $gd->$image_type;
    close $fh;
    print "Image written to '$out_file'.  Done.\n";
}
else {
    print $gd->$image_type;
}

=pod

=head1 AUTHOR

Ken Y. Clark E<lt>kclark@cpan.orgE<gt>

=cut