package AutomakeWorkspaceCreator;

# ************************************************************
# Description   : A Automake Workspace (Makefile) creator
# Author        : Chad Elliott
# Create Date   : 5/13/2002
# ************************************************************

# ************************************************************
# Pragmas
# ************************************************************

use strict;
use File::Basename;

use AutomakeProjectCreator;
use WorkspaceCreator;

use vars qw(@ISA);
@ISA = qw(WorkspaceCreator);

# ************************************************************
# Subroutine Section
# ************************************************************

sub workspace_file_name {
  my($self) = shift;
  return $self->get_modified_workspace_name('Makefile', '.am');
}


sub workspace_per_project {
  #my($self) = shift;
  return 1;
}


sub pre_workspace {
  my($self) = shift;
  my($fh)   = shift;
  my($crlf) = $self->crlf();

  print $fh '##', $crlf,
            '##  Process this file with automake', $crlf,
            '##', $crlf,
            $crlf,
            '##', $crlf,
            '## $Id$', $crlf,
            '##', $crlf,
            '## This file was generated by MPC.  Any changes made directly to', $crlf,
            '## this file will be lost the next time it is generated.', $crlf,
            '##', $crlf,
            '## MPC Command:', $crlf,
            "## $0 @ARGV", $crlf,
            '##', $crlf,
            $crlf,
            '## The number in AUTOMAKE_OPTIONS is the minimum required version automake', $crlf,
            '## needed to process this file.', $crlf,
            'AUTOMAKE_OPTIONS = 1.7 foreign', $crlf, $crlf;
}


sub write_comps {
  my($self)     = shift;
  my($fh)       = shift;
  my($projects) = $self->get_projects();
  my(@list)     = $self->sort_dependencies($projects);
  my($crlf)     = $self->crlf();
  my(%unique)   = ();
  my(@dirs)     = ();

  ## Get a unique list of directories while
  ## preserving the order of the original @list
  foreach my $dep (@list) {
    my($dir) = dirname($dep);
    if (!defined $unique{$dir}) {
      $unique{$dir} = 1;
      unshift(@dirs, $dir);
    }
  }

  ## Print out the subdirectories
  print $fh 'SUBDIRS =';
  foreach my $dir (@dirs) {
    print $fh " \\$crlf        $dir";
  }
  print $fh $crlf;
}


1;
