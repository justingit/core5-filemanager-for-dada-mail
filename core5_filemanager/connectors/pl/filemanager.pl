#!/usr/bin/perl

# use CGI::Carp qw(fatalsToBrowser);

use Carp qw(croak carp);

use FindBin;

use lib "$FindBin::Bin/../../cgi-bin/dada";
use lib "$FindBin::Bin/../../cgi-bin/dada/DADA/perllib";
use lib "$FindBin::Bin/../../cgi-bin/dada/DADA/App/Support";

use lib "$FindBin::Bin/../../../cgi-bin/dada";
use lib "$FindBin::Bin/../../../cgi-bin/dada/DADA/perllib";
use lib "$FindBin::Bin/../../../cgi-bin/dada/DADA/App/Support";

use lib "$FindBin::Bin/../../../../cgi-bin/dada";
use lib "$FindBin::Bin/../../../../cgi-bin/dada/DADA/perllib";
use lib "$FindBin::Bin/../../../../cgi-bin/dada/DADA/App/Support";

# <!-- tmpl_if additional_perllibs -->
# Additional Perl Libraries:
#<!-- tmpl_loop additional_perllibs -->
		use lib "<!-- tmpl_var name default='' -->";
# <!-- /tmpl_loop -->
#/ Additional Perl Libraries:
#<!-- /tmpl_if -->

#die $FindBin::Bin;

BEGIN {
    my $b__dir = ( getpwuid($>) )[7] . '/perl';
    push @INC, $b__dir . '5/lib/perl5',
      $b__dir . '5/lib/perl5/x86_64-linux-thread-multi', $b__dir . 'lib',
      map { $b__dir . $_ } @INC;
}

use DADA::Config;
use CGI;
use JSON;

use File::Basename;
use File::Find::Rule;
use File::Slurp;
use strict;

use Try::Tiny;

our $q;
my $t = 0;

&check_security();

sub check_security { 
	
	$q = CGI->new;
	# I bet this now has to be a json, something or other...
	require DADA::App::Guts; 

	$q->param('_csrf_token', $q->cookie('_csrf_token'));
	
    my ( $admin_list, $root_login, $checksout, $error_msg ) = DADA::App::Guts::check_list_security(
        -cgi_obj         => $q,
        -Function        => 'send_email send_url_email',
    );
	
    if ($checksout) {
		#... 
	}	
	else { 
		error("Sessioning Failed. Log in!"); 	
		exit();
	}
}


#Edit this with your values in
require 'filemanager_config.pl';
my $config    = $Filemanager::Config::config;
my $config_js = from_json(
    read_file( '../../scripts/filemanager.config.js', binmode => ':utf8' ),
    { utf8 => 1 } );

my $MODE_MAPPING = {
    ''        => \&root,
    getinfo   => \&getinfo,
    getfolder => \&getfolder,
    rename    => \&rename,
    delete    => \&delete,
    addfolder => \&addfolder,
    add       => \&add,
    download  => \&download
};

sub main {
    $q = CGI->new;
    my $method = $MODE_MAPPING->{ scalar $q->param('mode') } || \&root;
	
	# This is a kludge: 
	my $p = $q->param('path');
	warn '$p: ' . $p if $t; 
	# A url, with 
	#my $up = quotemeta($config->{url_path}); 
	# This is a thing that is happening, 
	if($p =~ m/^\/http\:\//){ 
		$p =~ s/^\/http\:\//http:\/\//;
		warn 'new one: ' . $p if $t;
		 $q->param('path', $p);
	}
	

    unless ( $q->param('mode') eq "download" || $q->param('mode') eq "add" ) {
        print $q->header('application/json');
    }
    &$method;
}

#?mode=getinfo&path=/UserFiles/Image/logo.png&getsize=true
#For now return image size info anyway
sub getinfo {
	
	warn "\nin getinfo\n" if $t; 
	
    return unless params_valid( [qw(path)] );

    my $filename = relative_file_name_from_url( scalar $q->param('path') );

    print_json( file_info($filename) );
}

sub file_info {
	
	warn 'in file_info' if $t;
	
    my $rel_filename = shift;
    my $abs_filename = absolute_file_name_from_relative($rel_filename);
    my $url_filename = url_from_relative_filename($rel_filename);
	

    my $info = image_info($abs_filename);
    my ( $fileparse_filename, $fileparse_dirs, $fileparse_suffix ) =
      fileparse($abs_filename);
    $fileparse_filename =~ /\.(.+)/;
    my $suffix = lc($1) || "";

    my $directory = -d $abs_filename;
    if ($directory) {
        $url_filename .= "/";
    }

    my $preview =
      $config_js->{icons}{path}
      . ( ($directory)
        ? $config_js->{icons}{directory}
        : $config_js->{icons}{default} );
    if ( grep { $suffix eq $_ } @{ $config_js->{images}->{imagesExt} } ) {
        $preview = $url_filename;
    }
    elsif ( -e '../../' . $config_js->{icons}{path} . $suffix . '.png' ) {
        $preview = $config_js->{icons}{path} . $suffix . '.png';
    }
	
	
	#my $return_path = 
	

    return {
        "Path"       => $url_filename,
        "Filename"   => $fileparse_filename,
        "File Type"  => $directory ? "dir" : $suffix,
        "Preview"    => $preview,
        "Properties" => {
            "Date Created"  => '',                #TODO
            "Date Modified" => '',                #"02/09/2007 14:01:06",
            "Height"        => $info->{height},
            "Width"         => $info->{width},
            "Size"          => -s $abs_filename
        },
        "Error" => "",
        "Code"  => 0
    };
}

sub test_rel { 
	my $fn = shift;
	my $upload_rel = $config_js->{options}->{fileRoot}; 
  	   $upload_rel =~ s/\/$//g; 
  	   $upload_rel = quotemeta($upload_rel);
	if($fn =~ !/^$upload_rel/){ 
		croak "relative wrong: " . $fn; 
	}	
}

sub test_abs { 
	my $fn = shift; 
	my $upload_abs = $config->{uploads_directory};
	   $upload_abs =~ s/\/$//g; 
	   $upload_abs = quotemeta($upload_abs);
	 
	if($fn !~ m/^$upload_abs/){ 
		croak "abs wrong: " . $fn; 
	}	
}

sub test_url { 
	
	my $url = shift; 
	my $upload_url = $config->{url_path};
	   $upload_url =~ s/\/$//g; 
	   $upload_url = quotemeta($upload_url);
	 
	if($url !~ m/^$upload_url/){ 
		croak "url wrong: " . $url; 
	}	
	
}

# ?mode=getfolder&path=/UserFiles/Image/&getsizes=true&type=images
#Ignoring type for now

sub getfolder {
    warn "\nin getfolder\n"
      if $t;

    return unless params_valid( [qw(path)] );

    my @directory_list = ();

	

    warn '$q->param(\'path\'): ' . $q->param('path') 
		if $t;

    my $rel_directory;
	
	my $fr = $config_js->{options}->{fileRoot};; 
	   $fr =~ s/\/$//;
	   $fr = quotemeta($fr);
	
    if ( $q->param('path') =~ m/^$fr/ ) {
		# is this already a relative dir? 
    }
    elsif($q->param('path') =~ m/^http/ ) {
        $rel_directory =
          relative_file_name_from_url( scalar $q->param('path') );
    }
	else { 
		# fake it, 
		$rel_directory = rel_fn_from_fn($rel_directory); 
		warn 'faking it: ' if $t; 
	}

    warn '$rel_directory: ' . $rel_directory
      if $t;

	 test_rel($rel_directory);


    my $directory = absolute_file_name_from_relative($rel_directory);
	test_abs($directory);


    my @directories = File::Find::Rule->maxdepth(1)->directory->in($directory);
    my @files       = File::Find::Rule->maxdepth(1)->file->in($directory);



    foreach my $dir (@directories) {
		
			
		my $just_dn = fn_from_rel_fn(relative_file_name_from_absolute($dir)); 
		warn '$just_dn; ' . $just_dn if $t; 
		# skip dot files/dirs
		if($just_dn =~ m/^\./){ 
			next; 
		}
				
        my $url_filename = url_from_absolute_filename($dir); 
		
		#die '$url_filename: ' . $url_filename; 
		
        #Skip current directory
		#warn 'looking at dir: ' . $dir; 
		#warn 'SAME1: ' . relative_file_name_from_absolute($dir); 
		#warn 'SAME2: ' . $rel_directory; 
		
        if(
			fn_from_rel_fn(relative_file_name_from_absolute($dir))
			eq fn_from_rel_fn($rel_directory)
		) { 
			next; 
		}

        push( @directory_list,
            file_info( relative_file_name_from_absolute($dir) ) );
    }

    foreach my $file (@files) {
		
		my $just_fn = fn_from_rel_fn(relative_file_name_from_absolute($file)); 
		warn '$just_fn; ' . $just_fn if $t; 
		# skip dot files/dirs
		if($just_fn =~ m/^\./){ 
			next; 
		}
		
		
		
        my $url_filename = url_from_absolute_filename($file);

# push(@directory_list, { $url_filename => file_info(relative_file_name_from_absolute($file)) });
        push( @directory_list,
            file_info( relative_file_name_from_absolute($file) ) );
    }

    print_json( \@directory_list );
}

# ?mode=rename&old=/UserFiles/Image/logo.png&new=id.png
sub rename {
    return unless params_valid( [qw(old new)] );
    my $path     = '';
    my $old_name = '';
    my $error    = 0;
    my $full_old = absolute_file_name_from_url( scalar $q->param('old') );
    ( $path, $old_name ) = ( $1, $2 )
      if $full_old =~ m|^ ( (?: .* / (?: \.\.?\z )? )? ) ([^/]*) |xs;
    my $new_name = $q->param('new');
    $new_name =~ s|^ .* / (?: \.\.?\z )? ||xs;
    $error = 1 if $new_name =~ /^\.?\.?\z/;
    my $full_new = remove_extra_slashes("$path/$new_name");

    $error ||= ( rename( $full_old, $full_new ) ) ? 0 : 1;

    print_json(
        {
            "Error"    => $error ? "Could not rename" : "No error",
            "Code"     => $error,
            "Old Path" => url_from_relative_filename(
                relative_file_name_from_absolute($full_old)
            ),
            "Old Name" => $old_name,
            "New Path" => url_from_relative_filename(
                relative_file_name_from_absolute($full_new)
            ),
            "New Name" => $new_name
        }
    );
}

#?mode=delete&path=/UserFiles/Image/logo.png
sub delete {
    return unless params_valid( [qw(path)] );
    my $full_old = absolute_file_name_from_url( scalar $q->param('path') );
    my $success;
    if ( -d $full_old ) {
        $success = rmdir $full_old;
    }
    else {
        $success = unlink $full_old;
    }

    print_json(
        {
            "Error" => $success ? "No error" : "Could not delete",
            "Code"  => !$success,
            "Path"  => scalar $q->param('path')
        }
    );
}

#Assuming this is the upload action? Documentation isn't much help
sub add {
    warn 'in add'
      if $t;

    return unless params_valid( [qw(currentpath newfile)] );

    warn 'still in add'
      if $t;

    my $path = $q->param('currentpath');
    warn '$path: ' . $path
      if $t;

    my $abs_path;
	# Nooooooo
    if ( $path =~ m/^http/ ) {
       $abs_path = absolute_file_name_from_url($path);
	   warn 'after absolute_file_name_from_url $abs_path: ' . $abs_path if $t;
    }
    else {
        $abs_path = absolute_file_name_from_relative($path);
    }

    warn '$abs_path: ' . $abs_path
      if $t;

    my $success = 0;

    my $lightweight_fh = $q->upload('newfile');
    my $filename       = $q->param('newfile');
    my $abs_filename   = r_ls($abs_path) . "/" . r_fs($filename);
    
	warn '$abs_path: ' . $abs_path if $t; 
	warn '$abs_filename: ' . $abs_filename if $t;
	
	# right? 
	$filename = r_ls($path) . "/" . r_fs($filename);
	
	# relative_file_name_from_absolute($abs_filename);

    my $buffer;

    # undef may be returned if it's not a valid file handle
    if ( defined $lightweight_fh ) {

        # Upgrade the handle to one compatible with IO::Handle:
        my $io_handle = $lightweight_fh->handle;
        open( OUTFILE, '>>', $abs_filename );
        while ( my $bytesread = $io_handle->read( $buffer, 1024 ) ) {
            print OUTFILE $buffer;
        }
        $success = 1;
    }

    warn '$success' . $success
      if $t;
    if ($t) {
        require Data::Dumper;
        warn Data::Dumper::Dumper(
            {
                Path  => $path,
                Name  => $filename,
                Error => $success ? "No error" : "Could not upload",
                Code  => !$success

            }
        );
    }

    print $q->header('text/html');
    print "<textarea>";
    print_json(
        {
            Path  => $path,
            Name  => $filename,
            Error => $success ? "No error" : "Could not upload",
            Code  => !$success

        }
    );
    print "</textarea>";

}

#Nice confusing path name for a folder!
# ?mode=addfolder&path=/UserFiles/&name=new%20logo.png
sub addfolder {
    
	warn 'in addfolder' if $t; 
	
	return unless params_valid( [qw(path name)] );

    my $path      = $q->param('path');
	warn '$path: ' . $path if $t;
	
    my $name      = $q->param('name');
	
	warn '$name: ' . $name if $t;
	
	
    my $full_path = absolute_file_name_from_relative($path);
	
	
    my $new_name  = $name;
	
	if($new_name =~ m/\.\./){ 
		die "no."
	}
	

    my $success = mkdir r_ls($full_path) . "/" . r_fs($new_name);

    print_json(
        {
            "Parent" => $path,
            "Name"   => $new_name,
            "Error"  => $success ? "No error" : "Could not add that folder",
            "Code"   => !$success
        }
    );
}

# ?mode=download&path=/UserFiles/new%20logo.png
sub download {
    return unless params_valid( ["path"] );

    my $full_path = absolute_file_name_from_url( scalar $q->param('path') );
    my $rel_path  = relative_file_name_from_url( scalar $q->param('path') );
    my $info      = file_info($rel_path);

# print $q->redirect(scalar  $q->param('path')); #Would be easier to just redirect

    print $q->header(
        -type       => 'application/x-download',
        -attachment => $info->{Filename}
    );

    open( DLFILE, "<$full_path" )
      || error("couldn't open the file for sending");
    my @fileholder = <DLFILE>;
    close(DLFILE);

    print @fileholder;

}

sub relative_file_name_from_url {
    warn "\nin relative_file_name_from_url\n"
      if $t;

    my $file = shift;
    warn '$file: ' . $file
      if $t;

    if ( $file =~ /\.\./g ) {
        error("Invalid file path");
        return undef;
    }
    warn '$file: ' . $file
      if $t;

    warn '$config->{url_path}: ' . $config->{url_path}
      if $t;

    my $qmeta_url_path = quotemeta( $config->{url_path} );

    $file =~ s/^$qmeta_url_path//;
	$file =~ s/^\///; 
	
	my $fr = $config_js->{options}->{fileRoot};; 
	   $fr =~ s/\/$//; 
		
	$file =  $fr . '/' . $file; 
	
    warn '$file: ' . $file                                             if $t;
    warn 'remove_extra_slashes($file): ' . remove_extra_slashes($file) if $t;
    return remove_extra_slashes($file);
}

sub fn_from_rel_fn { 
	
	warn 'in fn_from_rel_fn' if $t;
	my $fn = shift; 
	   $fn =~ s/\/$|^\///g; 
	
	warn 'fn_from_rel_fn $fn:' . $fn if $t;
	
	my $fr = $config_js->{options}->{fileRoot};
	   $fr =~ s/\/$|^\///g; 
	   warn 'fn_from_rel_fn $fr: ' . $fr if $t;
	   $fr = quotemeta($fr); 
	   
	   $fn =~ s/^$fr//; 
	   $fn =~ s/\/$|^\///g; 
	   
	   warn 'finally fn_from_rel_fn $fn: ' . $fn if $t; 
	   return $fn; 	   
}

sub rel_fn_from_fn { 
	my $fn = shift; 
	
	my $rel_fn = $config_js->{options}->{fileRoot} . '/' . $fn; 
	
	return $rel_fn; 
	
}

sub relative_file_name_from_absolute {
    
	# Relative just means releatice to example: 
	#/home/user/public_html/dada_mail_support_files/file_uploads
	
	warn "\nin relative_file_name_from_absolute\n" if $t;
	
	my $file = shift;
	
	warn '$file: ' . $file if $t; 
	
	warn '$config->{uploads_directory}: ' . $config->{uploads_directory} if $t; 
	
	my $abs_path = $config->{uploads_directory};
	   $abs_path =~ s/\/$//; 
    
	$file =~ s/^$abs_path//;
	$file =~ s/^\///;
	
	my $fr = $config_js->{options}->{fileRoot};
	# take off last slash: 
	$fr =~ s/\/$//; 
	
	warn '$fr: ' . $fr if $t;
		
	$file =  r_ls($fr) . '/' . r_fs($file); 
	
	warn '$file: ' . $file if $t;
	
    return remove_extra_slashes($file);
}


sub r_ls { 
	my $s = shift; 
	   $s =~ s/\/$//;
	   return $s; 
}
sub r_fs { 
	my $s = shift; 
	   $s =~ s/^\///;
	   return $s; 
}





sub absolute_file_name_from_url {
    warn "\nin absolute_file_name_from_url\n" if $t;

    my $file_path = shift;

    warn '$file_path: ' . $file_path if $t;

    if ( $file_path =~ /\.\./g ) {
        error("Invalid file path");
        return undef;
    }
	my $uploads_dir = $config->{uploads_directory}; 
	
	my $rel_fn      = relative_file_name_from_url($file_path); 
	my $just_fn     = fn_from_rel_fn($rel_fn);
	
    my $filename =  r_ls($uploads_dir) . '/' . r_fs($just_fn);
	  
	warn 'final absolute_file_name_from_url $filename: ' . $filename 
		if $t;  
	
    return remove_extra_slashes($filename);
}

sub absolute_file_name_from_relative {

	my $rel_fn = shift; 
   
    warn "\nin absolute_file_name_from_relative\n" 
		if $t;
	
	warn '$config->{uploads_directory}: ' . $config->{uploads_directory} if $t; 
	warn '$rel_fn: ' . $rel_fn if $t;
	
	# $fileRoot is something like: /dada_mail_support_files/file_uploads/
	my $fileRoot = $config_js->{options}->{fileRoot};
	   $fileRoot = r_ls($fileRoot); 
	   
	warn '$fileRoot: ' . $fileRoot if $t;
	$fileRoot = quotemeta($fileRoot);
		
	# $config->{uploads_directory} is something like, 
	# /home/user/public_html/dada_mail_support_files/file_uploads/	
	
	# I just want the filename: 
	$rel_fn =~ s/^$fileRoot//;	
	
	warn '$rel_fn: ' . $rel_fn if $t; 
	
	my $uploads_directory = $config->{uploads_directory} ; 
	
	# and then tack it on again: 
	my $abs_fn = r_ls($uploads_directory) . '/' . r_fs($rel_fn);
	
	warn '$abs_fn: ' . $abs_fn if $t;
	
    warn 'remove_extra_slashes($abs_fn): ' . remove_extra_slashes($abs_fn)
      if $t;
	  
    return remove_extra_slashes($abs_fn);
}

sub url_from_relative_filename {
    warn "\nin url_from_relative_filename\n"               
		if $t;
	
    my $filename = shift;
	warn '$filename: ' . $filename if $t;
	
	$filename =~ s/^\///;
	
    warn '$config->{url_path}: ' . $config->{url_path} if $t;
	
	
	$filename = fn_from_rel_fn($filename);
	
	warn '$filename: ' . $filename if $t; 
	
	my $url_path =  $config->{url_path}; 
	   $url_path =~ s/\/$//;
	   
    my $url = $url_path . '/' . $filename;

    warn 'finally $url: ' . $url if $t;

    return $url;

    #warn 'remove_extra_slashes($url): ' . remove_extra_slashes($url);

    #return remove_extra_slashes($url);
}

sub url_from_absolute_filename { 
	
	warn 'in url_from_absolute_filename' if $t; 
	
	
	my $fn = shift; 
	warn '$fn: ' . $fn if $t;  
	
	my $rfn = relative_file_name_from_absolute($fn);
	warn '$rfn: ' . $rfn  if $t; 
	
	my $url =  url_from_relative_filename($rfn);

	warn '$url: ' . $url if $t; 

	test_url($url); 
	
	return $url; 
}



sub remove_extra_slashes {
    my $filename = shift;
    $filename =~ s/\/\//\//g;

    #Strip ending slash too
    $filename =~ s/\/$//g;
    return $filename;
}

sub params_valid {
    my $params = shift;

    foreach my $param (@$params) {
        unless ( $q->param($param) ) {
            error("$param missing");
            return undef;
        }
    }

    return 1;
}

#return json error
sub root {
    error("Mode not specified");
}

sub error {
    my $error = shift;
    print_json(
        {
            "Error" => $error,
            "Code"  => -1
        }
    );
    $q->end_html;
    die "Couldn't carry on, " . $error;
}

sub print_json {
    my $hash = shift;

    my $json = JSON->new->convert_blessed->allow_blessed;

    print $json->encode($hash);
}

sub image_info {

    my $info = {};
    try {
        require Image::Info;
        $info = Image::Info::image_info();
    }
    catch {

    };

    return $info;

}

sub image_type {
    my $info = {};
    try {
        require Image::Info;
        $info = Image::Info::image_type();
    }
    catch {

    };

    return $info;

}
main();
